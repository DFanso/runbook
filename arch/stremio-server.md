# Stremio Cache Server on Arch (via Docker)

A single shared `stremio-server` runs on this Arch box. All Stremio clients on
the LAN / hotspot point at it for their **Streaming Server URL**, so a torrent
is fetched and cached **once** for the whole household instead of separately
per-device.

## Why Docker (and not the AUR package)

`stremio-service` exists in the AUR but pulls in the full desktop GUI. We just
want the headless server. The community image
[`tsaridas/stremio-docker`](https://hub.docker.com/r/tsaridas/stremio-docker)
ships exactly that: server + caching, nothing else.

## Prerequisites

- `docker` (`pacman -S docker`) and the daemon enabled:

  ```bash
  sudo systemctl enable --now docker
  ```

- A writable directory for the cache. I use `/mnt/media/stremio` because
  `/mnt/media` is the 1 TB NTFS drive (see [ntfs-auto-mount.md](ntfs-auto-mount.md)):

  ```bash
  sudo mkdir -p /mnt/media/stremio
  sudo chown $USER:$USER /mnt/media/stremio
  ```

## Run

```bash
sudo docker pull tsaridas/stremio-docker:latest

sudo docker run -d \
  --name stremio-server \
  --restart unless-stopped \
  -p 11470:11470 \
  -p 12470:12470 \
  -v /mnt/media/stremio:/root/.stremio-server \
  -e NO_CORS=1 \
  -e SERVER_URL=http://10.42.0.1:11470/ \
  tsaridas/stremio-docker:latest
```

Ports:

- `11470` — HTTP control API + streams (use this from clients)
- `12470` — HTTPS variant with a self-signed cert (Stremio web needs this for
  mixed-content when stremio.com loads over HTTPS)

`SERVER_URL` is the URL clients on the hotspot reach the server through; swap
for `http://192.168.1.<server>:11470/` if your hotspot iface differs.

`--restart unless-stopped` is enough — Docker brings it back on reboot, so no
separate systemd unit is needed.

## Cache size

Default is a tiny 2 GB. Bump it via the running server's REST API (writes
through to `server-settings.json` in the volume so it survives container
recreate):

```bash
# 50 GB
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"cacheSize":53687091200}' \
  http://127.0.0.1:11470/settings
```

Verify:

```bash
curl -s http://127.0.0.1:11470/settings | jq '.values.cacheSize'
```

The cache lives at `/mnt/media/stremio/stremio-cache/`. Drop the whole dir to
wipe it; the server will recreate it.

## Verify reachability

```bash
# from the server itself
curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:11470/settings

# from anywhere on the LAN / hotspot
curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://<server-lan-ip>:11470/settings
```

`200 OK` means it's reachable. UFW does not need an explicit rule — Docker's
publish flag (`-p 11470:11470`) installs its own iptables rules that bypass UFW.

## Point clients at it

In each Stremio client (iOS / Android / Desktop / Web):

**Settings → Streaming Server → Server URL**

```
http://10.42.0.1:11470/
```

(Use whichever IP the client reaches the server on — `10.42.0.1` for hotspot
clients via `ap0`, or the wired LAN IP for laptops.)

Once a stream starts the client gets it from the local server, the local server
fetches it from the swarm, and every other client watching the same thing
streams from the same cache.

## Operate

```bash
# logs
sudo docker logs -f stremio-server

# restart
sudo docker restart stremio-server

# update to latest image
sudo docker pull tsaridas/stremio-docker:latest
sudo docker stop stremio-server && sudo docker rm stremio-server
# then re-run the docker run from above

# stop persistently
sudo docker stop stremio-server
sudo docker update --restart=no stremio-server
```

## Notes

- All container egress on this host is transparently routed through V2rayA's
  tproxy (see the v2raya nft table), so torrent traffic exits via the V2rayA
  upstream node instead of the bare home IP. If you need raw direct egress
  for the server (faster swarms), mark the container's traffic and exclude it
  from the tproxy chain.
- The server can also transcode (HLS), but on this CPU-only box the bundled
  hardware-accel probe fails — software transcoding only. For 4K HEVC remuxing,
  prefer a direct-play-capable client (Stremio Desktop/iOS) over transcoded
  playback.
