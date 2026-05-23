# HasH-Arch SDDM 2FA — patch progress (branch `hash-2fa`, SDDM v0.21.0)

Goal: after the password, SDDM shows a **popup** for the TOTP code, by relaying
PAM's extra (non-password) prompts from the helper → daemon → greeter and back.
Key fact (verified in source): `PamBackend::converse` already packages prompts
into `AuthRequest`/`AuthPrompt` and sends them via `m_app->request()`. We only
need to (a) forward prompts the daemon can't auto-answer to the greeter, and
(b) feed the greeter's answer back into the request.

## ✅ Step 1 — protocol (DONE, committed)
`src/common/Messages.h`: appended
- `GreeterMessages::PromptResponse` (greeter → daemon)
- `DaemonMessages::PromptRequest`  (daemon → greeter)

## Step 2 — greeter side  `src/greeter/GreeterProxy.{h,cpp}`
- **GreeterProxy.h**: add
  ```cpp
  signals:   void promptRequested(const QString &message, bool secret);
  public slots: void respondToPrompt(const QString &answer);
  ```
- **GreeterProxy.cpp**, in the `switch (DaemonMessages(message))` (~line 158),
  add a case mirroring `InformationMessage`'s read:
  ```cpp
  case DaemonMessages::PromptRequest: {
      QString msg; bool secret = false;
      input >> msg >> secret;
      emit promptRequested(msg, secret);
      break;
  }
  ```
- Add the slot mirroring how `login()` writes to the socket:
  ```cpp
  void GreeterProxy::respondToPrompt(const QString &answer) {
      SocketWriter(d->socket) << quint32(GreeterMessages::PromptResponse) << answer;
  }
  ```

## Step 3 — daemon side  `src/daemon/` (Display + SocketServer + the Auth glue)
- When the helper's `AuthRequest` arrives with a prompt that is NOT the login
  password (the password is already known from `Login`), instead of failing:
  emit it to the greeter via `SocketServer` as `PromptRequest` (write message + secret).
- Add a `PromptResponse` case in `SocketServer`'s greeter-message reader that
  feeds the answer back into the pending `AuthRequest` response (resume converse).
- Files: `src/daemon/SocketServer.cpp` (add PromptResponse read + a
  `promptRequested` signal/`sendPromptRequest()`), `src/daemon/Display.cpp`
  (connect Auth's request → forward unknown prompts; connect socket response →
  Auth). Check `src/auth/Auth*` for where responses are set on the request.

## Step 4 — theme  `Sweet-Qt6/Login.qml`
```qml
Connections { target: sddm
    function onPromptRequested(message, secret) { codePopup.msg = message; codePopup.open() }
}
Popup { id: codePopup; property string msg
    /* rounded HasH box; TextField echoMode = secret?Password:Normal; OK button */
    onAccepted: sddm.respondToPrompt(codeField.text)
}
```

## Step 5 — PAM  `/etc/pam.d/sddm`
Replace the `forward_pass` line with the password module first, then GA:
```
auth        include     system-login
auth        required    pam_google_authenticator.so nullok
```

## Build / install / TEST (user, root + TTY fallback)
```
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_MAN_PAGES=OFF
cmake --build build -j$(nproc)
sudo cmake --install build         # replaces the login manager
```
Test by locking / switch-user FIRST; keep Ctrl+Alt+F2 open. Then PR upstream.

## Refined UX requirements (from review)
- Code entry is **borderless** — just the field, no box, no separate label
  (the prompt is the placeholder). DONE in hash-theme/popuptest.qml.
- **Auto-submit + close** once the full code (codeLen, default 6) is entered. DONE.
- Must reuse the **same styling as the existing password field** (read the Sweet
  password TextField/PlasmaComponents and apply identical look) — TODO.
- Presented as a **slide animation to a new input field** (password field slides
  → code field), on BOTH the **SDDM login** (Sweet-Qt6 Login.qml) and the
  **lock screen** (Sweet LockScreenUi.qml). The popup is a stand-in; final form is
  an inline second field in a StackView/transition. TODO.

## Roadmap: Windows-Hello-style unlock (face / fingerprint / PIN)
All via PAM, so they slot into the same /etc/pam.d/{sddm,kde} stack and benefit
from the prompt-relay (greeter can show "Look at the camera", "Touch sensor", etc).
- **Face**: Howdy (AUR `howdy`). Needs a good cam (IR ideal). PAM: `auth sufficient pam_howdy.so`
  ABOVE the password line so face succeeds first, password is fallback. Enroll: `sudo howdy add`.
- **Fingerprint**: `fprintd` + `pam_fprintd.so` (needs a reader). PAM: `auth sufficient pam_fprintd.so`.
  Enroll: `fprintd-enroll`.
- **PIN**: no native Linux PIN. Options: a separate `pam_exec`/`pam_oath` short-secret, or
  a dedicated numeric credential checked by a small PAM module. Design TBD.
- Order in PAM (sddm + kde): faillock → [howdy sufficient] → [fprintd sufficient] →
  pam_unix (password) → [google-authenticator] → faillock. Greeter shows the right
  prompt via PromptRequest. All root-install + hardware-enroll = user steps.

## Status (daemon relay done)
- ✅ Step 3 daemon relay committed (Display::slotRequestChanged type-based + relay,
  slotPromptResponse, SocketServer::promptRequest/promptResponse).
- BUILD prereq: `sudo pacman -S extra-cmake-modules`, then
  `cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_MAN_PAGES=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && cmake --build build -j`
- TODO: theme integration (sliding code field into Sweet-Qt6 Login.qml + LockScreenUi.qml),
  then user `sudo cmake --install build` + logout-test (TTY open); PAM forward_pass -> plain.

## Lock screen (kscreenlocker) — QML-only, NO fork needed
Confirmed: `kscreenlocker_greet` exposes the conversation API — signals
`promptForSecret(msg)`, `prompt(msg)`, `infoMessage`, `succeeded`, `failed`, and
method `authenticator.respond(text)` (plus the old `tryUnlock(password)`).
Active lock theme: `/usr/share/plasma/look-and-feel/Sweet/contents/lockscreen/LockScreenUi.qml`
(it currently uses `authenticator.tryUnlock(password)` at ~line 263; auth Connections
at ~line 43 with onFailed/onMessage/onError — NO promptForSecret handler yet).

Patch plan (mirror the Login.qml integration):
1. Add a `property bool twoFactorActive: false` + a code field (reuse the theme's
   password field component for identical styling), hidden, slides in, echoMode
   Password, auto-submits at 6 digits.
2. Add to the `Connections { target: authenticator }`:
   `function onPromptForSecret(msg) { if (msg looks like a code / not the first
   password prompt) { twoFactorActive = true; codeField.forceActiveFocus() } }`
   and on code submit/auto-submit call `authenticator.respond(codeField.text)`.
   (tryUnlock answers the password; the code prompt then fires promptForSecret.)
3. Enable 2FA on the lock screen's PAM: `/etc/pam.d/kde` currently has NO 2FA — add
   `auth required pam_google_authenticator.so nullok` after its password line
   (back up first; keep password fallback).
4. Test by locking (Meta+L) — password, then slide to code. Lock screen is lower
   risk than login (you can reboot to a TTY), but still back up /etc/pam.d/kde.
