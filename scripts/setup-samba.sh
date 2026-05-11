#!/bin/bash
# Install smb.conf, validate, enable services.
# Run from the repo root so the relative path to configs/smb.conf resolves:
#   sudo bash scripts/setup-samba.sh

set -e

SMB_CONF_SRC="$(dirname "$0")/../configs/smb.conf"

install -m 644 -o root -g root "$SMB_CONF_SRC" /etc/samba/smb.conf
echo "Installed /etc/samba/smb.conf"

echo "---"
echo "Validating config:"
testparm -s /etc/samba/smb.conf 2>&1 | head -30

echo "---"
systemctl enable --now smb
systemctl enable --now nmb
echo "Services: $(systemctl is-active smb) $(systemctl is-active nmb)"

echo "---"
echo "Listening ports:"
ss -tlnp | grep -E ':(139|445)\b' || echo "  (none yet — service may still be coming up)"

echo "---"
echo "Don't forget: sudo smbpasswd -a <user>"
echo "And open UFW: sudo ufw allow from 192.168.1.0/24 to any port 445 proto tcp"
