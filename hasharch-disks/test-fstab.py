#!/usr/bin/env python3
"""Dry-run test for the hash-disks-helper logic.

Exercises the fstab add/remove/refusal paths AND the destructive-op guards
(format / partition / relabel refuse the system disk; relabel validates the
filesystem) WITHOUT ever touching the real /etc/fstab or any real disk. Run as
a normal user:  python3 test-fstab.py

The system-disk guard normally shells out to findmnt/lsblk. For the test we
monkeypatch the helper's detection so we can simulate a known system disk and a
known data disk deterministically, and we stub subprocess.run so no real mkfs/
parted/relabel ever executes.
"""
import importlib.util
from importlib.machinery import SourceFileLoader
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
_path = os.path.join(HERE, "hash-disks-helper")
loader = SourceFileLoader("helper", _path)
spec = importlib.util.spec_from_loader("helper", loader)
H = importlib.util.module_from_spec(spec)
loader.exec_module(H)

SAMPLE = """\
# Static information about the filesystems.
# <file system>             <dir>     <type>  <options>             <dump> <pass>
UUID=11111111-aaaa-bbbb-cccc-000000000001  /      ext4  rw,relatime           0 1
UUID=22222222-aaaa-bbbb-cccc-000000000002  /boot  vfat  rw,relatime,fmask=0022 0 2
UUID=33333333-aaaa-bbbb-cccc-000000000003  /home  ext4  rw,relatime           0 2
"""

PASS = 0
FAIL = 0


def ok(msg):
    global PASS
    PASS += 1
    print(">> OK: " + msg)


def bad(msg):
    global FAIL
    FAIL += 1
    print("!! FAIL: " + msg)


# ───────────────────────── fstab dry-run (unchanged behaviour) ─────────────────
def test_fstab():
    tmp = tempfile.mkdtemp(prefix="hash-disks-fstab-")
    fstab = os.path.join(tmp, "fstab")
    with open(fstab, "w") as f:
        f.write(SAMPLE)
    H.FSTAB = fstab
    media_mp = os.path.join(tmp, "Media")

    print("\n# add NTFS 'Media' drive -> %s" % media_mp)
    rc = H.cmd_fstab_add("44444444-aaaa-bbbb-cccc-000000000004", media_mp,
                         "ntfs-3g", "defaults")
    if rc == 0 and os.path.isdir(media_mp):
        ok("media added, mount-point created")
    else:
        bad("media add rc=%d" % rc)
    txt = open(fstab).read()
    if media_mp in txt and "nofail" in txt.split("# hash-disks")[0].splitlines()[-1] \
            and "/boot" in txt and (" /      ext4" in txt or "/ " in txt):
        ok("nofail forced, root & boot intact")
    else:
        bad("fstab content wrong after add")

    print("\n# refuse to hijack root (mount point '/')")
    try:
        H.cmd_fstab_add("55555555-aaaa-bbbb-cccc-000000000005", "/", "ext4", "defaults")
        bad("should have refused root")
    except SystemExit:
        ok("refused root mount point")

    print("\n# remove the media entry")
    rc = H.cmd_fstab_remove("44444444-aaaa-bbbb-cccc-000000000004")
    after = open(fstab).read()
    if rc == 0 and media_mp not in after and "/home" in after:
        ok("media removed, home intact")
    else:
        bad("remove failed")
    shutil.rmtree(tmp, ignore_errors=True)


# ─────────────────── destructive-op guards (simulated disks) ───────────────────
def with_simulated_disks():
    """Monkeypatch the helper so /dev/sda* is the SYSTEM disk and /dev/sdb* is a
    DATA disk, and so no real subprocess runs. Returns a list of recorded argv."""
    recorded = []

    SYS_DISK = "/dev/sda"
    SYS_PARTS = {"/dev/sda1", "/dev/sda2"}

    H.valid_device = lambda dev: dev.startswith("/dev/sd")
    H.system_disks = lambda: {SYS_DISK}

    def whole_disk_of(part):
        if part.startswith("/dev/sda"):
            return "/dev/sda"
        if part.startswith("/dev/sdb"):
            return "/dev/sdb"
        return ""
    H._whole_disk_of = whole_disk_of
    H._findmnt_source = lambda target: ("/dev/sda2" if target == "/" else "")
    H.is_mounted = lambda dev: False
    H._refuse_if_any_part_mounted = lambda disk: None

    class FakeRun:
        def __init__(self, argv, **kw):
            recorded.append(list(argv))
            self.returncode = 0
            self.stdout = ""
            self.stderr = ""

    H.subprocess.run = lambda argv, **kw: FakeRun(argv, **kw)
    H.shutil.which = lambda name: "/usr/bin/" + name   # pretend all tools present
    return recorded


def expect_refusal(label, fn):
    try:
        fn()
        bad(label + " — should have refused")
    except SystemExit as e:
        if e.code == 9:
            ok(label + " (exit 9)")
        else:
            bad(label + " — refused with wrong code %s (want 9)" % e.code)


def expect_ok(label, fn):
    try:
        rc = fn()
        if rc == 0:
            ok(label)
        else:
            bad(label + " — rc=%s" % rc)
    except SystemExit as e:
        bad(label + " — unexpectedly refused (exit %s)" % e.code)


def test_guards():
    recorded = with_simulated_disks()

    print("\n# FORMAT must refuse a partition on the system disk")
    expect_refusal("format /dev/sda1 refused",
                   lambda: H.cmd_format("/dev/sda1", "ntfs", "Media"))

    print("\n# FORMAT is allowed on a data-disk partition")
    expect_ok("format /dev/sdb1 allowed",
              lambda: H.cmd_format("/dev/sdb1", "ntfs", "Media", "1000", "1000"))

    print("\n# FORMAT rejects an unsupported filesystem")
    try:
        H.cmd_format("/dev/sdb1", "zfs", "X")
        bad("format should reject zfs")
    except SystemExit as e:
        ok("format rejected unsupported fs (exit %s)" % e.code) if e.code == 2 \
            else bad("wrong code for unsupported fs: %s" % e.code)

    print("\n# FORMAT rejects an invalid label")
    try:
        H.cmd_format("/dev/sdb1", "ext4", "bad/label;rm -rf")
        bad("format should reject invalid label")
    except SystemExit as e:
        ok("format rejected invalid label (exit %s)" % e.code) if e.code == 2 \
            else bad("wrong code for bad label: %s" % e.code)

    print("\n# PARTITION ops must refuse the whole system disk")
    expect_refusal("part-table /dev/sda refused",
                   lambda: H.cmd_part_table("/dev/sda", "gpt"))
    expect_refusal("part-new /dev/sda refused",
                   lambda: H.cmd_part_new("/dev/sda", "0%", "100%"))
    expect_refusal("part-del /dev/sda refused",
                   lambda: H.cmd_part_del("/dev/sda", "1"))

    print("\n# PARTITION ops are allowed on a data disk")
    expect_ok("part-table /dev/sdb allowed",
              lambda: H.cmd_part_table("/dev/sdb", "gpt"))
    expect_ok("part-new /dev/sdb allowed",
              lambda: H.cmd_part_new("/dev/sdb", "0%", "100%"))

    print("\n# RELABEL refuses the system disk, validates fs, allows data disk")
    expect_refusal("relabel /dev/sda1 refused",
                   lambda: H.cmd_relabel("/dev/sda1", "ext4", "X"))
    try:
        H.cmd_relabel("/dev/sdb1", "weirdfs", "X")
        bad("relabel should reject unknown fs")
    except SystemExit as e:
        ok("relabel rejected unknown fs (exit %s)" % e.code) if e.code == 2 \
            else bad("wrong code: %s" % e.code)
    expect_ok("relabel /dev/sdb1 ext4 allowed",
              lambda: H.cmd_relabel("/dev/sdb1", "ext4", "NewLabel"))

    print("\n# POWER-OFF refuses the system disk")
    expect_refusal("power-off /dev/sda refused",
                   lambda: H.cmd_power_off("/dev/sda"))

    print("\n# net-mount refuses a protected mount point")
    expect = False
    try:
        H.cmd_net_mount("cifs", "//srv/share", "/", "")
        bad("net-mount should refuse '/'")
    except SystemExit as e:
        ok("net-mount refused '/' (exit %s)" % e.code)

    # sanity: the mkfs/parted argv we recorded never targeted /dev/sda
    for argv in recorded:
        if any(str(x).startswith("/dev/sda") for x in argv):
            bad("a recorded command touched the system disk: %r" % argv)
            break
    else:
        ok("no recorded command ever touched the system disk")


def main():
    test_fstab()
    test_guards()
    print("\n==================== SUMMARY ====================")
    print("PASS: %d   FAIL: %d" % (PASS, FAIL))
    if FAIL:
        print("SOME CHECKS FAILED")
        return 1
    print("All dry-run checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
