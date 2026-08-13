# server-dash (hotspot monitor)

Self-hosted dashboard for the V2rayA hotspot: CPU/RAM/power, per-device live
rates, **all-time usage**, Wi-Fi info, latency, Stremio/Comet cards, and
**timed device bans**.

- UI: `http://192.168.1.3:8080`
- Repo: `/home/dfanso/git/server-dash` (`https://github.com/dfansoo/server-dash`)
- Binary: `/home/dfanso/git/server-dash/backend/target/release/server-dash`
- Unit: `/etc/systemd/system/server-dash.service`
- Secrets: `/etc/systemd/system/server-dash.service.d/secrets.conf` (0600, root)

## Operate

```bash
sudo systemctl start server-dash
sudo systemctl stop server-dash
systemctl status server-dash --no-pager
journalctl -u server-dash -f
curl -s localhost:8080/api/health
```

`Restart=on-failure` does **not** come back after `SIGTERM` / `kill`. Always
start it with systemd so it picks up `secrets.conf` (V2rayA + Comet admin).

If you started the binary by hand (no secrets), Comet stats / V2rayA login
will be thin until you `sudo systemctl start server-dash`.

## Rebuild

```bash
cd /home/dfanso/git/server-dash/frontend && bun run build
cd /home/dfanso/git/server-dash/backend && cargo build --release --offline
sudo systemctl restart server-dash
```

`frontend/dist` and some `backend/src/*.rs` files are root-owned from older
deploys. If `bun run build` hits `EACCES`, rename `dist` on the same filesystem
then rebuild:

```bash
mv /home/dfanso/git/server-dash/frontend/dist /home/dfanso/git/server-dash/frontend/dist.rootbak
mkdir /home/dfanso/git/server-dash/frontend/dist
cd /home/dfanso/git/server-dash/frontend && bun run build
```

## Devices — all-time usage

`GET /api/clients` returns currently associated stations **and** every MAC
seen since tracking started. Lifetime rx/tx live in SQLite:

`/home/dfanso/git/server-dash/data/history.db` → table `device_usage`

`iw` session counters reset on reconnect, so the backend stores the last
session counters and adds deltas (or the new session total if the counter
went backwards). A background sampler runs every 5s even if nobody has the
page open.

All-time totals start from when this feature shipped (2026-08-13). Older
usage cannot be reconstructed.

## Temp-ban a device

On the Devices table: **Ban…** → 5m / 15m / 1h / 6h / 24h. **Unban** clears it.

```bash
# Ban 15 minutes
curl -sS -X POST localhost:8080/api/clients/ban \
  -H 'Content-Type: application/json' \
  -d '{"mac":"aa:bb:cc:dd:ee:ff","minutes":15}'

# Clear
curl -sS -X POST localhost:8080/api/clients/unban \
  -H 'Content-Type: application/json' \
  -d '{"mac":"aa:bb:cc:dd:ee:ff"}'
```

Bans persist in `device_bans` in the same SQLite file. While a ban is active
the backend deauths with `iw dev ap0 station del <mac>` and re-kicks every 2s
if they reconnect.

### Kick needs passwordless sudo

`iw station del` is `CAP_NET_ADMIN`. The dashboard runs as `dfanso`, so install
this once (copy-paste as one line):

sudo install -m 440 /home/dfanso/git/server-dash/deploy/sudoers-server-dash-iw /etc/sudoers.d/server-dash-iw

Same thing, shorter:

sudo /home/dfanso/git/server-dash/deploy/install-iw

Without that, the ban still **saves** but the device stays associated
(`sudo: a password is required`). After installing sudoers, ban again (or wait
up to 2s for the enforcer).

Do **not** casually ban the phone/laptop you are using on the hotspot or you
will kick yourself.

## Git

```bash
cd /home/dfanso/git/server-dash
git status
git log -5 --oneline
```

`origin` is `https://github.com/dfansoo/server-dash.git`.

`gh auth` on this box is stale (keyring token invalid, and a PAT without
`read:org` cannot `gh auth login`). Push with the token as the HTTPS password
and **disable** the `gh` credential helper:

```bash
git -c credential.helper= -c credential.https://github.com.helper= \
  push https://<user>:<token>@github.com/dfansoo/server-dash.git HEAD:main
```

Some `.git/objects/??` dirs are root-owned. If `git commit` says
`insufficient permission for adding an object`, clone to `/tmp`, commit there,
push, leave the working tree as-is.

## Related

- Hotspot boot: [hotspot-autoboot.md](hotspot-autoboot.md)
- Comet card / tunnel: [comet-stremio-addon.md](comet-stremio-addon.md)
- Stremio cache: [stremio-server.md](stremio-server.md)
