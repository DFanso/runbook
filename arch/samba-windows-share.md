# Samba share for Windows on Arch

Expose `/mnt/media` as a network drive for a Windows PC on the LAN.

## Install

```bash
sudo pacman -S samba
```

Arch's samba package does **not** ship a default `/etc/samba/smb.conf` — you have to create it.

## smb.conf

See [configs/smb.conf](../configs/smb.conf). Key settings:

- `security = user` + `map to guest = never` — password-required, no anonymous access
- `interfaces = lo enp4s0f1` + `bind interfaces only = yes` — listen on LAN only, not on tunnels/hotspot
- `valid users = <user>` on the share — only that user can connect

Replace `enp4s0f1` with your actual LAN interface (`ip -4 addr`).

Install + validate + start:

```bash
sudo install -m 644 /path/to/smb.conf /etc/samba/smb.conf
testparm -s /etc/samba/smb.conf
sudo systemctl enable --now smb nmb
ss -tlnp | grep -E ':(139|445)\b'
```

## Set the Samba password

Separate from the Linux login password. Required to authenticate from Windows.

```bash
sudo smbpasswd -a dfanso
```

## Firewall (UFW)

UFW defaults to `INPUT DROP`. Even if `systemctl is-active ufw` says inactive, the iptables rules may still be loaded — `sudo iptables -L INPUT` will reveal a `DROP` policy and ufw chains.

Allow SMB from the LAN only (not the whole world):

```bash
sudo ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment 'Samba SMB'
sudo ufw allow from 192.168.1.0/24 to any port 139 proto tcp comment 'Samba NetBIOS'
```

Port 445 alone is sufficient for modern Windows; 139 is legacy NetBIOS.

## Connect from Windows

PowerShell:

```powershell
Test-NetConnection 192.168.1.3 -Port 445   # should be TcpTestSucceeded : True
net use M: \\192.168.1.3\media /user:dfanso /persistent:yes
```

Or File Explorer → This PC → Map network drive → `\\192.168.1.3\media`, check "Reconnect at sign-in" and "Connect using different credentials".

## Debugging

- Server-side share visible? `smbclient -L //127.0.0.1 -N`
- Logs: `sudo journalctl -u smb -e` and `/var/log/samba/log.<client>`
- TCP path: `Test-NetConnection` from Windows — ping passing but TCP failing means firewall, not network.
