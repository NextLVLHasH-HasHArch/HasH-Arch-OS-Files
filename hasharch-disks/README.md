# HasH-Disks

A comprehensive disk-management tool for HasH-Arch (think GNOME Disks / KDE
Partition Manager, in the HasH dark/rounded style) — mount drives and USB
sticks, inspect per-device detail and SMART health, format and (re)partition
non-system disks, relabel and power-off removable media, make NTFS drives
writable as you, and mount SMB/NFS network shares — without ever touching
`fstab`, `parted` or `udisksctl` by hand. Part of the HasH-Arch settings suite
(Software Center · Security · Accounts · Disks).

## Pages (sidebar)

- **Drives** — every disk/partition: device, label, size, filesystem, mount
  point, used/free bar, mounted state. Mount/Unmount, Mount-on-boot, *Make
  writable as me* (NTFS), and a **Details** button → per-device detail panel.
- **Details** (per device) — model, serial, bus, rotational/SSD, partition
  table type (GPT/MBR), UUID, partition type, used/free, live mount state, all
  sibling partitions, and guarded actions (Relabel / Format / Health / Eject).
- **Format & Partition** — format a partition (NTFS/exFAT/ext4/FAT32/Btrfs),
  relabel, delete a partition, create a partition, new GPT table. The **system
  disk is hidden** here. Every action requires a **typed confirmation**.
- **Health** — SMART status (PASSED/FAILED), temperature, power-on hours and
  reallocated sectors via `smartctl` (hidden, with an install offer, when
  `smartmontools` is missing).
- **Network shares** — add an SMB/CIFS or NFS mount; credentials are saved
  root-only (600); optional fstab entry with `nofail` + `_netdev`.

## Components

- **`hash-disks`** — PyQt6 GUI (dark/rounded HasH style). Never run as root.
- **`hash-disks-helper`** — root helper invoked by the GUI through `pkexec`
  for the few privileged operations (fstab edits, fixed-disk mounts, the NTFS
  writable fix, `fsck`).
- **`hash-disks.desktop`** — launcher entry (Settings → Disks).

## Engine

- **udisks2** (`udisksctl mount/unmount -b`) for on-demand, no-root removable media.
- **`lsblk -J -O`** to enumerate devices; **`blkid`** / UUID for stable identifiers.
- **`/etc/fstab`** edits via the helper: timestamped backup, `findmnt --verify`
  validation, UUID-based, **always `nofail`**, and `/` `/boot` entries are never touched.

## Destructive-op safety (non-negotiable)

Format, partition-table ops, relabel and power-off go through the helper via
`pkexec`, require an explicit **typed confirmation** in the GUI, and the helper
**independently** computes the disk backing `/`, `/boot` and `/boot/efi` (via
`findmnt` + `lsblk -s`, unwinding LVM/dm/raid to physical disks) and **refuses**:

- to **format/relabel** any partition whose whole disk is a system disk;
- to run any **partition-table** op (`mkpart`/`rm`/`mklabel`) on a system disk;
- to **power-off** a system disk;
- to touch any device that is currently mounted (for the relevant ops).

The GUI's confirmation and hiding of the system disk are *in addition to* this
helper-side guard — the helper never trusts the GUI. Format wipes old
signatures (`wipefs -a`) then runs the right `mkfs.*`. Labels are validated
against a conservative character set before reaching `mkfs`/relabel tools.

## fstab safety (non-negotiable)

Every managed entry is written as:

    UUID=<uuid> <mountpoint> <fstype> <opts>,nofail,x-systemd.device-timeout=10 0 2  # hash-disks

Before replacing `/etc/fstab` the helper:
1. backs it up to `/etc/fstab.hash-bak-<YYYYmmdd-HHMMSS>`,
2. validates the candidate with `findmnt --verify` plus a structural parse,
3. refuses to write if validation fails,
4. never edits or removes a line whose mount point is `/`, `/boot`, `/boot/efi`, `/efi`.

Managed entries are tagged with a trailing `# hash-disks` comment so they can be
found, replaced and removed without disturbing hand-written entries.

## Dependencies

- `udisks2` (required) — removable mounting/power-off without root.
- `ntfs-3g` (NTFS read/write, the "Make writable as me" fix, `mkfs.ntfs`/`ntfslabel`).
- `polkit` + `pkexec`, `util-linux` (lsblk/blkid/findmnt/fsck/wipefs), `parted` —
  partition ops.
- `e2fsprogs`/`dosfstools`/`exfatprogs`/`btrfs-progs` — for the matching `mkfs.*`
  and relabel tools (only the ones you actually use are needed).
- `smartmontools` (optional) — SMART health; the Health page offers to install
  it via the Software Center when missing.
- `cifs-utils` / `nfs-utils` (optional) — SMB / NFS network shares.

## Install

    install -m755 hash-disks hash-disks-helper ~/.local/bin/
    install -m644 hash-disks.desktop ~/.local/share/applications/
    update-desktop-database ~/.local/share/applications 2>/dev/null || true

## Phases

- **P1** (done) — drive list + udisks mount/unmount + choose mount point.
- **P2** (done) — fstab auto-mount (UUID, `nofail`) + NTFS writable fix + fsck.
- **P3** (done) — per-device detail, SMART health, format, partition create/
  delete + new table, relabel, eject/power-off, NTFS-as-user, network shares.
- **Deferred** — non-destructive **partition resize/move**; System Settings KCM;
  GUI free-space picker for `part-new` (currently start/end fields).
