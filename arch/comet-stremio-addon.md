# Comet Stremio Addon (self-hosted, Docker)

Comet is a fast torrent/debrid search addon for Stremio. Self-hosted with PostgreSQL backend and a Cloudflare tunnel for HTTPS install URLs.

## Location

- Repo: `/home/dfanso/Projects/comet/` (cloned from `https://github.com/g0ldyy/comet`)
- Config: `/home/dfanso/Projects/comet/deployment/.env`
- Credentials: `/home/dfanso/comet-credentials.txt`

## Containers

| Container | Image | Port |
|---|---|---|
| `comet` | `g0ldyy/comet` | `8000` |
| `comet-postgres` | `postgres:18-alpine` | internal |
| `cloudflared` | `cloudflare/cloudflared` | host network |

## Start / Stop

```bash
# Start
cd /home/dfanso/Projects/comet/deployment
docker compose up -d

# Stop
docker compose down

# Logs
docker compose logs -f comet
```

## Cloudflare Tunnel

Cloudflared runs as a standalone container (not in compose), on **host networking** so
its traffic is picked up by V2rayA's TPROXY rules:

```bash
docker run -d --name cloudflared --restart unless-stopped --network host \
  --dns 1.1.1.1 --dns 8.8.8.8 \
  cloudflare/cloudflared:latest tunnel --no-autoupdate \
  --edge-ip-version 4 --url http://localhost:8000

# Get current tunnel URL
docker logs cloudflared 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | tail -1

# Restart to get a new URL
docker restart cloudflared && sleep 12
docker logs cloudflared 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | tail -1
```

Flags that matter:

- `--edge-ip-version 4` — the IPv6 edge fails through V2rayA. Without this,
  cloudflared tries an IPv6 edge first, times out, and the tunnel can land in a
  state where the URL resolves but returns **Error 1033** (edge not connected).
- `--dns 1.1.1.1` — with host networking Docker rewrites the container's
  `resolv.conf` (the host uses the `127.0.0.53` systemd-resolved stub, which
  Docker refuses to inherit) and the substitute resolver it picks intermittently
  times out. Pinning a public resolver fixes lookup failures at startup.
- Always take the **last** URL from the logs — logs accumulate across restarts and
  every quick tunnel gets a fresh hostname.

> A `trycloudflare.com` quick tunnel has no uptime guarantee and its hostname changes
> on every restart. For something stable, create a named tunnel against a real
> Cloudflare account + domain.

> The tunnel URL is a random `*.trycloudflare.com` subdomain and changes on every restart.
> The server-dash dashboard shows the current URL and has a restart button.

## Install into Stremio

1. Open `http://192.168.1.3:8000/configure` (LAN) or the trycloudflare.com URL
2. Select **TorBox** as debrid service and paste your API key
3. Click **Install** — or in Stremio go to Addons and paste the manifest URL directly

## Scrapers enabled

- Torrentio (public, no key)
- Zilean (public DHT cache)
- TorBox personal library (API key in `.env`)

## UFW

Port 8000 is open for Stremio LAN installs:

```bash
ufw allow 8000/tcp comment "Comet Stremio addon"
```

## V2rayA routing — Docker bridges bypass the proxy

**Gotcha worth remembering for any container on this box.** V2rayA's nftables
`tp_rule` chain returns early on Docker interfaces:

```
iifname "br-*"    return
iifname "docker*" return
iifname "veth*"   return
```

So **any container on a bridge network egresses straight out the ISP link**, no
matter what subnet it's on — the `interface` set never gets consulted. Only
host-originated traffic (the `tp_out` chain) is proxied.

That's why `comet` uses `network_mode: host` and postgres is published on
`127.0.0.1:5432` instead of being reached over a bridge. Loopback is exempt from
TPROXY, so the DB connection stays local.

Verify which path a container is actually using:

```bash
# Host (should be the v2rayA exit IP)
curl -s https://api.ipify.org; echo

# Comet container (must match the host)
docker exec comet python -c \
  "import urllib.request; print(urllib.request.urlopen('https://api.ipify.org').read().decode())"
```

If the two differ, the container is leaking to the ISP link.

## What actually uses bandwidth

Comet only returns a **list of stream URLs**. The video itself is fetched by the
Stremio client directly from the TorBox CDN — it never passes through this server
or the tunnel. So:

- Routing Comet through V2rayA only covers scraper/TorBox **API** calls (small).
- The multi-GB video stream goes over whatever connection the **playback device**
  uses. Only devices on the hotspot (`ap0`, `10.42.0.0/24`) are TPROXY'd through
  V2rayA; a device on the router LAN (`192.168.1.0/24`) uses the normal ISP line.

To force video through V2rayA as well, enable Comet's stream proxy
(`PROXY_DEBRID_STREAM=True` + `PROXY_DEBRID_STREAM_PASSWORD`). That pulls every
stream through this server and the V2rayA node — it burns the node's bandwidth
twice over, so only do it deliberately.

## server-dash integration

The Comet card on the dashboard (`http://192.168.1.3:8080`) polls `/api/comet`
every 10s and shows:

- Reachability + addon version
- Current Cloudflare tunnel URL, with copy and **Restart tunnel** buttons
- Index stats — torrents indexed, searches in the last 24h, avg seeders, avg size
- Movies/series split, and proxied stream count when the stream proxy is on
- Top 4 sources by torrent count

### Admin API auth

The stats come from Comet's `/admin/api/metrics` and `/admin/api/connections`,
which need the admin session cookie. server-dash logs in itself
(`POST /admin/login`, form-encoded `password`), caches the `admin_session`
cookie, and re-authenticates on a 401.

The password is read from `COMET_ADMIN_PASSWORD`. Like the v2rayA credentials it
lives in the root-only systemd drop-in, **never** in the repo:

```bash
# /etc/systemd/system/server-dash.service.d/secrets.conf  (0600, root)
Environment=COMET_ADMIN_PASSWORD=<ADMIN_DASHBOARD_PASSWORD from comet .env>
```

```bash
systemctl daemon-reload && systemctl restart server-dash
curl -s localhost:8080/api/comet | python3 -m json.tool   # stats should be non-null
```

Without the variable the card degrades gracefully — liveness and tunnel URL
still work, `stats` is just `null`.

> Don't set `PUBLIC_METRICS_API=True` as a shortcut. The Cloudflare tunnel makes
> port 8000 reachable from the internet, so that would publish the index stats
> publicly.
