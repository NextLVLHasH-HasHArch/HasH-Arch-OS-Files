# HasH-Arch — SDDM 2FA "code popup" patch

Goal: after the user types their **password**, SDDM shows a **second prompt / popup**
for the TOTP verification code (instead of `forward_pass` where password+code go in
one field). Stock SDDM can't do this: its greeter↔daemon protocol passes a single
password and the PAM conversation in `sddm-helper` ignores any extra prompt. This
patch relays PAM's extra prompts to the greeter.

Fork: `git clone https://github.com/sddm/sddm && cd sddm` (branch off, e.g. `hash-2fa`).
Build deps on Arch: `qt6-base qt6-declarative pam systemd extra-cmake-modules`.

---

## 1. `src/common/Messages.h` — new message types
Add to the daemon→greeter `enum DaemonMessages` and greeter→daemon `enum GreeterMessages`:

```cpp
// DaemonMessages (daemon -> greeter)
PromptRequest,        // QString message, bool secret   (PAM is asking something extra)
// GreeterMessages (greeter -> daemon)
PromptResponse,       // QString answer
```

## 2. `src/helper/backend/PamBackend.cpp` — forward extra prompts
In `PamBackend::converse()` the loop builds responses to each PAM message. Today the
first ECHO_OFF prompt gets the stored password and others fail. Change it so that any
ECHO_OFF/ECHO_ON prompt that is **not** the initial login password is sent to the
greeter and the loop blocks for the answer:

```cpp
case PAM_PROMPT_ECHO_OFF:
case PAM_PROMPT_ECHO_ON: {
    if (m_app->session()...isPrimaryPasswordPrompt(msg[i])) {       // existing behaviour
        response[i].resp = strdup(qPrintable(password));
    } else {
        // NEW: ask the greeter (relayed up through HelperApp -> daemon -> greeter)
        QString answer = m_app->backend()->requestPrompt(
            QString::fromLocal8Bit(msg[i]->msg),
            msg[i]->msg_style == PAM_PROMPT_ECHO_OFF /*secret*/);
        response[i].resp = strdup(qPrintable(answer));
    }
    break;
}
```
`requestPrompt()` is a new blocking method on the backend that emits up to `HelperApp`,
which forwards over the existing helper socket to the daemon.

## 3. `src/daemon/` — relay to the greeter
- `HelperApp` gains `requestPrompt(msg, secret)` → emits a signal the `Display`/`Session`
  forwards to `SocketServer`.
- `SocketServer::sendPromptRequest(msg, secret)` writes a `PromptRequest` message to the
  greeter socket; `SocketServer` already has a slot loop — add a `PromptResponse` case
  that calls back into the helper (resume `converse`).

## 4. `src/greeter/` — expose to QML
In the greeter's `GreeterProxy` (the object thirds themes use as `sddm`):
```cpp
signals:  void promptRequested(const QString &message, bool secret);
public slots: void respondToPrompt(const QString &answer);   // sends PromptResponse
```
Wire `SocketHelper`'s incoming `PromptRequest` → `emit promptRequested(...)`,
and `respondToPrompt` → write `PromptResponse`.

## 5. Theme — `Sweet-Qt6/Login.qml` (or our fork)
```qml
Connections {
    target: sddm
    function onPromptRequested(message, secret) {
        codePopup.label = message; codePopup.open()
    }
}
Popup {
    id: codePopup; property string label
    /* rounded dark box matching HasH; a TextField (echoMode based on `secret`)
       and an OK button: */
    onAccepted: sddm.respondToPrompt(codeField.text)
}
```

## 6. PAM — `/etc/pam.d/sddm`
Switch from the one-field workaround to a real second prompt:
```
# was: auth required pam_google_authenticator.so nullok forward_pass
auth        include     system-login
auth        required    pam_google_authenticator.so nullok
```
(password module runs first → google-authenticator then issues "Verification code:"
→ relayed to the popup.)

## 7. Build / install / test (KEEP A TTY FALLBACK)
```
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_MAN_PAGES=OFF
cmake --build build -j
sudo cmake --install build
```
Test by switching user / locking — DO NOT log fully out until verified; `Ctrl+Alt+F2`
TTY login has no 2FA and is your recovery path. Then open a PR upstream — SDDM has
long-standing requests for PAM multi-prompt/2FA support.

## Interim (today, no fork)
Keep `forward_pass`: type `password` + `6-digit code` in the one field.
