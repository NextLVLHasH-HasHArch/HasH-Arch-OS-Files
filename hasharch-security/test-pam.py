#!/usr/bin/env python3
"""Dry-run test for the hash-security-helper PAM logic.

Copies sample PAM stacks to /tmp, points the helper at THOSE copies, and
exercises the safety-critical paths WITHOUT ever touching the real
/etc/pam.d/*.  Run as a normal user:

    python3 test-pam.py

This is the most important verification in the project: it asserts the
lock-out-safety invariants — password fallback is never lost, the helper
REFUSES to touch the TTY `login` stack, enabling adds only our tagged line,
disabling removes only our tagged line, and restore rolls back cleanly.
"""
import importlib.util
from importlib.machinery import SourceFileLoader
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
# the helper has no .py extension, so give importlib an explicit source loader
_path = os.path.join(HERE, "hash-security-helper")
loader = SourceFileLoader("helper", _path)
spec = importlib.util.spec_from_loader("helper", loader)
H = importlib.util.module_from_spec(spec)
loader.exec_module(H)

# Sample stacks mirroring this machine's real layout (SDDM already has the GA
# line from the installer; kde/sudo are clean includes).
SAMPLE = {
    "sddm": """\
#%PAM-1.0

auth        include     system-login
auth        required    pam_google_authenticator.so nullok
-auth       optional    pam_gnome_keyring.so

account     include     system-login
password    include     system-login
session     include     system-login
""",
    "kde": """\
#%PAM-1.0

auth       include                     system-local-login
account    include                     system-local-login
password   include                     system-local-login
session    include                     system-local-login
""",
    "sudo": """\
#%PAM-1.0
auth		include		system-auth
account		include		system-auth
session		include		system-auth
""",
    # TTY login — must NEVER be edited.  Present so we can prove the refusal.
    "login": """\
#%PAM-1.0

auth       requisite    pam_nologin.so
auth       include      system-local-login
account    include      system-local-login
session    include      system-local-login
password   include      system-local-login
""",
}

PASS = 0
FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  >> OK: " + msg)
    else:
        FAIL += 1
        print("  !! FAIL: " + msg)


def setup():
    tmp = tempfile.mkdtemp(prefix="hash-security-pam-")
    for svc, body in SAMPLE.items():
        with open(os.path.join(tmp, svc), "w") as f:
            f.write(body)
    # Redirect the helper at our copies — never the real /etc/pam.d.
    H.PAMDIR = tmp
    return tmp


def read(tmp, svc):
    with open(os.path.join(tmp, svc)) as f:
        return f.read()


def section(t):
    print("\n===== %s =====" % t)


def main():
    tmp = setup()
    print("Working on PAM copies in %s\n" % tmp)

    # ── 1. enable TOTP on the lock (kde) surface ────────────────────────────
    section("enable TOTP on lock (kde)")
    rc = H.cmd_enable("totp", "lock")
    txt = read(tmp, "kde")
    print(txt.rstrip())
    check(rc == 0, "enable returned 0")
    check("pam_google_authenticator.so" in txt, "GA line added")
    check(H.TAG in txt, "managed marker present")
    check("system-local-login" in txt, "password include (pam_unix path) kept")
    check(H.has_password_fallback(txt), "password fallback still reachable")
    # the GA line must come AFTER the password include (TOTP layered after)
    ga_idx = next(i for i, l in enumerate(txt.splitlines())
                  if "pam_google_authenticator" in l)
    pw_idx = next(i for i, l in enumerate(txt.splitlines())
                  if "include" in l and "system-local-login" in l and "auth" in l)
    check(ga_idx > pw_idx, "TOTP layered AFTER the password line")

    # ── 2. idempotency: enabling again is a no-op ───────────────────────────
    section("enable TOTP again (idempotent)")
    H.cmd_enable("totp", "lock")
    txt2 = read(tmp, "kde")
    check(txt2.count("pam_google_authenticator.so") == 1,
          "no duplicate GA line after second enable")

    # ── 3. enable fingerprint too; both bio (sufficient) + totp coexist ─────
    section("enable fingerprint on lock (kde)")
    H.cmd_enable("fingerprint", "lock")
    txt3 = read(tmp, "kde")
    print(txt3.rstrip())
    check("pam_fprintd.so" in txt3, "fprintd line added")
    check("sufficient" in [l.split()[1] for l in txt3.splitlines()
                           if "pam_fprintd" in l][0], "fingerprint is sufficient")
    check("pam_faillock.so preauth" in txt3, "faillock preauth bracket present")
    check("pam_faillock.so authfail" in txt3, "faillock authfail bracket present")
    check(H.has_password_fallback(txt3), "password fallback still reachable")

    # ── 4. disable TOTP removes ONLY the managed GA line ────────────────────
    section("disable TOTP on lock (kde)")
    H.cmd_disable("totp", "lock")
    txt4 = read(tmp, "kde")
    print(txt4.rstrip())
    check("pam_google_authenticator.so" not in txt4, "GA line removed")
    check("pam_fprintd.so" in txt4, "fingerprint line still present")
    check(H.has_password_fallback(txt4), "password fallback still reachable")

    # ── 5. disable fingerprint -> managed block fully gone, file clean ──────
    section("disable fingerprint on lock (kde)")
    H.cmd_disable("fingerprint", "lock")
    txt5 = read(tmp, "kde")
    print(txt5.rstrip())
    check(H.TAG not in txt5, "all managed lines removed")
    check("pam_faillock" not in txt5, "faillock brackets removed when no methods")
    check(read(tmp, "kde").strip() != "", "file not emptied")
    check(H.has_password_fallback(txt5), "password fallback still reachable")

    # ── 6. SDDM already has the installer GA line; enabling face keeps it ───
    section("enable face on login (sddm) — installer GA line preserved")
    H.cmd_enable("face", "login")
    sd = read(tmp, "sddm")
    print(sd.rstrip())
    check("pam_howdy.so" in sd, "howdy line added on sddm")
    check("system-login" in sd, "sddm system-login include kept (pam_unix path)")
    check(H.has_password_fallback(sd), "sddm password fallback still reachable")

    # ── 7. THE CRITICAL GUARANTEE: the TTY login FILE is never touched ──────
    # Surfaces are login(->sddm) / lock(->kde) / sudo; NONE map to
    # /etc/pam.d/login, so the TTY recovery path is structurally unreachable.
    section("TTY /etc/pam.d/login never touched + protected names refused")
    login_before = read(tmp, "login")
    for surf, svc in H.SURFACE_FILE.items():
        check(svc != "login", "surface %r does NOT map to the TTY login file" % surf)
    # passing a protected service NAME directly (not a real surface) is refused
    for prot in ("system-login", "system-local-login", "system-auth"):
        try:
            H.resolve_surface(prot)
            check(False, "resolve_surface(%r) should have refused" % prot)
        except SystemExit as e:
            check(e.code == 6, "resolve_surface(%r) refused (exit %s)" % (prot, e.code))
    # the graphical-login surface IS editable and lands on sddm, never the TTY
    check(H.resolve_surface("login") == "sddm",
          "surface 'login' resolves to sddm (graphical), not the TTY login file")
    check(read(tmp, "login") == login_before, "TTY login file is byte-for-byte UNCHANGED")

    # ── 8. refuse to disable the password fallback ──────────────────────────
    section("REFUSE to disable the password fallback")
    try:
        H.cmd_disable("password", "lock")
        check(False, "disabling password should have refused")
    except SystemExit as e:
        check(e.code == 6, "refused to disable password (exit %s)" % e.code)

    # ── 9. validation rejects a stack with no password fallback ─────────────
    section("validation rejects a passwordless stack")
    bad = "#%PAM-1.0\nauth required pam_howdy.so\nauth required pam_faillock.so authfail\n"
    ok, detail = H.validate_candidate(bad, "kde")
    check(not ok, "validate_candidate rejects passwordless stack (%s)" % detail.split('\n')[0])
    good = SAMPLE["kde"]
    ok2, _ = H.validate_candidate(good, "kde")
    check(ok2, "validate_candidate accepts a normal stack")

    # ── 10. restore rolls back to the latest backup ─────────────────────────
    section("restore rolls back the sudo surface")
    sudo_orig = read(tmp, "sudo")
    H.cmd_enable("totp", "sudo")
    after = read(tmp, "sudo")
    check("pam_google_authenticator.so" in after, "totp added to sudo before restore")
    rc = H.cmd_restore("sudo")
    restored = read(tmp, "sudo")
    check(rc == 0, "restore returned 0")
    check("pam_google_authenticator.so" not in restored, "restore removed the GA line")
    check(restored.strip() == sudo_orig.strip(), "sudo restored to original content")

    # ── 11. PIN enable is still refused (no untested credential path) ───────
    section("PIN enable is REFUSED (lockout safety)")
    try:
        H.cmd_enable("pin", "lock")
        check(False, "enable pin should have refused")
    except SystemExit as e:
        check(e.code == 8, "enable pin refused (exit %s)" % e.code)
    pin_kde = read(tmp, "kde")
    check("pam_pin" not in pin_kde and "pin" not in H.current_managed_methods(pin_kde),
          "no PIN line written to the stack")

    # ── 12. install allow-list — arbitrary packages are REFUSED ─────────────
    section("install allow-list refuses arbitrary packages")
    check(set(H.INSTALLABLE) >= {"howdy", "fprintd"},
          "howdy + fprintd are installable")
    for bad in ("bash", "sudo", "openssh", "pam"):
        try:
            H.cmd_install(bad)
            check(False, "install(%r) should have refused" % bad)
        except SystemExit as e:
            check(e.code == 2, "install(%r) refused (exit %s)" % (bad, e.code))

    # ── 13. howdy-config only accepts allow-listed, validated keys ──────────
    section("howdy-config validates keys/values")
    check(set(H.HOWDY_CONFIG_KEYS) == {"certainty", "dark_threshold"},
          "only certainty + dark_threshold are settable")
    try:
        H.cmd_howdy_config("model_path", "/etc/passwd")
        check(False, "howdy-config should refuse unknown key")
    except SystemExit as e:
        check(e.code == 2, "howdy-config refused unknown key (exit %s)" % e.code)
    try:
        H.cmd_howdy_config("certainty", "999")  # out of range
        check(False, "howdy-config should refuse out-of-range value")
    except SystemExit as e:
        check(e.code == 2, "howdy-config refused bad value (exit %s)" % e.code)

    # ── 14. _valid_user rejects shell-y / path-y usernames ──────────────────
    section("_valid_user rejects unsafe usernames (argv defence-in-depth)")
    check(H._valid_user("hash"), "plain username accepted")
    for bad in ("", "root; rm -rf /", "../etc", "a b", "user$(id)", "x" * 40):
        check(not H._valid_user(bad), "rejected unsafe user %r" % bad)

    # ── 15. the new install/enroll subcommands NEVER edit a PAM file ────────
    # We stub the actual command runners so nothing real is installed/run, then
    # exercise every new subcommand and assert the PAM copies are byte-identical.
    section("install/enroll/faillock subcommands do not touch PAM files")
    before = {svc: read(tmp, svc) for svc in SAMPLE}
    calls = []
    orig_stream, orig_run, orig_which = H._run_stream, H.subprocess.run, H.shutil.which
    H._run_stream = lambda argv, env=None: calls.append(argv) or 0
    H.subprocess.run = lambda *a, **k: type("R", (), {"returncode": 1, "stdout": "", "stderr": ""})()
    H.shutil.which = lambda name: "/usr/bin/" + name  # pretend tools exist
    for fn, args in [(H.cmd_install, ("fprintd",)), (H.cmd_install, ("howdy",)),
                     (H.cmd_howdy_add, ("hash",)), (H.cmd_howdy_clear, ("hash",)),
                     (H.cmd_howdy_config, ("certainty", "3")),
                     (H.cmd_fprint_enroll, ("hash",)),
                     (H.cmd_fprint_delete, ("hash",)),
                     (H.cmd_faillock_reset, ("hash",))]:
        try:
            fn(*args)
        except SystemExit:
            pass
    H._run_stream, H.subprocess.run, H.shutil.which = orig_stream, orig_run, orig_which
    check(len(calls) >= 6, "subcommands invoked their wrapped tools (%d calls)" % len(calls))
    check(all("/etc/pam.d" not in " ".join(c) for c in calls),
          "no wrapped command references /etc/pam.d")
    for svc in SAMPLE:
        check(read(tmp, svc) == before[svc],
              "%s PAM file unchanged by install/enroll path" % svc)

    shutil.rmtree(tmp, ignore_errors=True)
    print("\n========================================")
    print("PAM dry-run: %d passed, %d failed." % (PASS, FAIL))
    print("========================================")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
