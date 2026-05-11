# Auto-mount NTFS drive on Arch

External USB drive formatted NTFS. Mount via fstab so it comes up before services that depend on it (Plex, Samba).

## Identify the drive

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL
sudo blkid -s UUID -o value /dev/sdXN
```

## Driver: `ntfs3` (kernel) vs `ntfs-3g` (FUSE)

The in-kernel `ntfs3` driver is faster and ships with modern kernels — no extra package needed. Check it's available:

```bash
modinfo ntfs3 | head -3
```

## fstab line

```
UUID=<UUID>  /mnt/media  ntfs3  defaults,uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=10  0 0
```

Why these options:

- `uid=1000,gid=1000` — owner is the regular user; NTFS doesn't carry Linux ownership, so it's assigned at mount time
- `umask=022` — directories `755`, files `644`. Other users (including `plex`, UID 961) get read+traverse
- `nofail` — boot doesn't hang if the drive is disconnected
- `x-systemd.device-timeout=10` — give the drive 10s to appear, then move on

## Apply

```bash
sudo mkdir -p /mnt/media
# append the line to /etc/fstab via sudo (see scripts/setup-ntfs-mount.sh)
sudo systemctl daemon-reload
sudo mount /mnt/media
```

See [scripts/setup-ntfs-mount.sh](../scripts/setup-ntfs-mount.sh) for an idempotent helper.

## Notes / gotchas

- If the drive was hibernated by Windows, `ntfs3` mounts it read-only. Boot Windows, shut down properly (not hibernate), and retry.
- `ls -la /mnt/media` may show files owned by `root root` even with `uid=1000` — that's a display quirk. Permissions still apply via `umask`.
- After plugging/unplugging frequently, `nofail` keeps the boot clean.
