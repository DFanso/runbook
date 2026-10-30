# runbook

Personal notes for things I set up on my machines. Future-me's reference.

## Arch

- [Plex Media Server](arch/plex-server.md) — install, enable, web setup
- [NTFS auto-mount via fstab](arch/ntfs-auto-mount.md) — external drive at `/mnt/media`
- [Samba share for Windows](arch/samba-windows-share.md) — map drive over LAN
- [Stremio cache server (Docker)](arch/stremio-server.md) — shared streaming cache for the household
- [Hotspot auto-boot (systemd)](arch/hotspot-autoboot.md) — bring up `ap0` (5 GHz ch 36) + v2rayA TPROXY plumbing on reboot, gated on v2rayA being healthy
- [v2rayA upstream DNS outage](arch/v2raya-upstream-dns.md) — proxy down because the VPS hostname resolves wrong: diagnose, purge 1.1.1.1, pin DNS
- [Comet Stremio addon (Docker)](arch/comet-stremio-addon.md) — self-hosted debrid addon with TorBox + Cloudflare tunnel for HTTPS
- [server-dash](arch/server-dash.md) — hotspot dashboard on `:8080`, all-time per-device usage, timed bans

## Configs

Sanitized config snippets in [configs/](configs/), and reusable helper scripts in [scripts/](scripts/).
