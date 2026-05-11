# Plex Media Server on Arch

## Install

`plex-media-server` lives in the AUR. With `yay`:

```bash
yay -S plex-media-server
```

If yay's final install step fails on a non-tty sudo, install the built package manually:

```bash
sudo pacman -U /home/<user>/.cache/yay/plex-media-server/*.pkg.tar.zst
```

The package creates a `plex` system user (UID/GID 961) and a `plexmediaserver.service` unit.

## Enable and start

```bash
sudo systemctl enable --now plexmediaserver
systemctl status plexmediaserver --no-pager | head -15
```

Verify it's listening on 32400:

```bash
ss -tln | grep 32400
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:32400/web/index.html
```

## First-time web setup

Plex refuses non-localhost connections during the setup wizard.

- On the server itself: `http://localhost:32400/web`
- From another machine, SSH-tunnel first:

  ```bash
  ssh -L 32400:localhost:32400 <user>@<server-ip>
  ```

  Then open `http://localhost:32400/web` on the laptop.

Sign in with the Plex account, name the server, add libraries pointing at the media directories.

## Library paths

Media lives at `/mnt/media` — see [ntfs-auto-mount.md](ntfs-auto-mount.md). Make sure the `plex` user can read these paths; the NTFS mount uses `umask=022` so `r-x` on "other" covers it.

## Remote access (optional)

Plex settings → Remote Access → enable. UPnP first; if the router doesn't support it, manually forward TCP **32400** to the server.
