#!/bin/bash
# Idempotently mount an NTFS drive at /mnt/media via fstab.
# Edit UUID/MOUNTPOINT/UID_GID below before running.
#
# Usage: sudo bash setup-ntfs-mount.sh

set -e

UUID="A01255FD1255D93C"      # blkid -s UUID -o value /dev/sdXN
MOUNTPOINT="/mnt/media"
OPTS="defaults,uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=10"

LINE="UUID=${UUID} ${MOUNTPOINT} ntfs3 ${OPTS} 0 0"

mkdir -p "$MOUNTPOINT"

if grep -qF "$UUID" /etc/fstab; then
    echo "fstab already references $UUID — skipping append"
else
    echo "$LINE" >> /etc/fstab
    echo "Appended to /etc/fstab:"
    echo "  $LINE"
fi

systemctl daemon-reload

if mountpoint -q "$MOUNTPOINT"; then
    echo "$MOUNTPOINT already mounted"
else
    mount "$MOUNTPOINT"
    echo "$MOUNTPOINT mounted"
fi

echo "---"
echo "Contents of $MOUNTPOINT:"
ls -la "$MOUNTPOINT"
