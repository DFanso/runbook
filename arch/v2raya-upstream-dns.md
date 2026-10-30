# v2rayA down: upstream hostname resolves to the wrong IP

v2rayA on the Arch box (`192.168.1.3`) connects to the VPS by **hostname**
(`v2ray.<domain>:444`, VLESS + TLS). If that name stops resolving to the VPS,
the whole hotspot loses internet even though every local service is "active".
The Windows PC kept working the whole time because NetMod dials the VPS **IP**
directly — so "it works on my PC" does not clear the server's upstream.

## Incident: 2026-10-28

- The domain hit its expiry date. The registrar (Namecheap) swapped the zone to
  a parking lander (`ns1.lander.d.parity.domains`) → `v2ray.<domain>` resolved
  to two parking IPs instead of the VPS.
- Paying + moving DNS back (Cloudflare NS) fixed the authoritative answer, but
  resolvers kept serving the parking IPs:
  - `1.1.1.1` / `1.1.1.3` cached the parking NS for up to 3600s → purged (below).
  - The **router** (`192.168.1.1` / `fe80::1` via RA) kept serving stale answers
    long after Cloudflare/Google were correct. systemd-resolved rotates through
    every link DNS server, so the proxy went *intermittently* down — some
    connections to the dead IPs, some to the VPS.
- Fix: purge Cloudflare's cache, pin the box's DNS away from the router,
  restart v2rayA.

**Prevent it:** keep auto-renew on for the domain.

## Diagnose

Everything below runs on the box as root.

```bash
systemctl is-active v2raya
pgrep -a v2ray                                    # v2raya + v2ray core
curl -sS -m 12 -x socks5h://127.0.0.1:20170 -o /dev/null -w '%{http_code}\n' https://www.google.com
```

Then look at **where the core is actually dialing**:

```bash
ss -tan '( dport = :444 )' | awk 'NR>1{print $1, $5}' | sort | uniq -c
getent ahostsv4 v2ray.<domain>
```

- Many `SYN-SENT` to an IP that isn't the VPS → DNS problem (this page).
- `SYN-SENT` to the right IP → VPS / its firewall / ISP path problem.
- `ESTAB` to the right IP but proxy still fails → protocol/config mismatch.

### Local probes lie (TPROXY)

v2rayA's transparent proxy catches the box's **own** outbound traffic, so
`bash -c '</dev/tcp/host/port'`, `nc`, `openssl s_client` etc. report "open"
for anything — the TCP handshake is with v2ray, not the remote. Bypass it by
setting the same fwmark v2rayA uses for its own sockets (`SO_MARK` = `0x80`):

```bash
python3 - <<'EOF'
import socket, ssl
for ip in ["<vps-ip>"]:
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, 36, 128); s.settimeout(6)  # 36 = SO_MARK
    s.connect((ip, 444))
    ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    print(ip, ctx.wrap_socket(s, server_hostname="netflix.com").version())
EOF
```

Same trick for DNS: send the query from a marked UDP socket to ask a resolver
directly; an unmarked query to `1.1.1.1` / `8.8.8.8` gets redirected by the
`familydns` outbound to `1.1.1.3` (adult filter) and you're testing the wrong
resolver.

The Windows PC can't be used as a probe either: NetMod's tun2socks
(`TAP-Windows`, gw `10.4.2.1`) accepts every TCP connect locally — even
`1.2.3.4:444` "connects".

### Which resolver is stale

Ask each one directly (marked socket, as above) for `v2ray.<domain>`:
`1.1.1.1`, `1.1.1.3`, `8.8.8.8`, `9.9.9.9`, `192.168.1.1`, `fe80::1%enp4s0f1`,
plus `127.0.0.53` (systemd-resolved). The box's DNS path:

```
getent / v2ray core ("localhost" DNS)
  → systemd-resolved 127.0.0.53
    → link DNS on enp4s0f1 (pinned: 1.1.1.1 8.8.8.8)
      → v2rayA familydns outbound → 1.1.1.3
```

v2rayA's own DNS block also sends `v2ray.<domain>` to `208.67.220.220:5353`
and `119.29.29.29` over TCP, but the core still dials the proxy server via
the system resolver.

## Fix

### 1. Purge Cloudflare's public resolver cache

No auth needed. Purge both the zone's NS and the A record:

```bash
curl -s -X POST 'https://one.one.one.one/api/v1/purge?domain=<domain>&type=NS'
curl -s -X POST 'https://one.one.one.one/api/v1/purge?domain=v2ray.<domain>&type=A'
```

(Web form: https://one.one.one.one/purge-cache/.) Takes a few seconds; verify
with a marked query to `1.1.1.1` **and** `1.1.1.3` — Families has its own cache.

### 2. Keep the router out of the box's DNS

The router's upstream (ISP) can lag for hours. The box uses systemd-networkd
(no NetworkManager / `nmcli`), so pin DNS with a drop-in:

`/etc/systemd/network/20-ethernet.network.d/dns.conf`

```ini
[Network]
DNS=1.1.1.1 8.8.8.8

[DHCPv4]
UseDNS=no

[DHCPv6]
UseDNS=no

[IPv6AcceptRA]
UseDNS=no
```

Apply without bouncing the link (hotspot clients stay up), then flush:

```bash
sudo resolvectl dns enp4s0f1 1.1.1.1 8.8.8.8
sudo resolvectl flush-caches
resolvectl dns enp4s0f1          # expect: 1.1.1.1 8.8.8.8 (no fe80::1)
```

The drop-in takes over on the next boot / `networkctl reconfigure`. Undo:
delete it and `sudo networkctl reload`.

### 3. Restart v2rayA so the core re-resolves

```bash
sudo systemctl restart v2raya    # drops hotspot connections for a few seconds
```

Restarting while resolvers are still stale just re-caches the bad answer —
fix DNS first. The v2ray core's DNS cache can hold the old answer for its TTL
(~60s) even without a restart.

### Quick bypass

If DNS can't be fixed right away, point v2rayA's server entry at the VPS IP in
the UI (`http://192.168.1.3:2017`), keeping port 444 and SNI `netflix.com`.
Remember to switch it back to the hostname later.

## Verify

```bash
getent ahostsv4 v2ray.<domain>                                  # VPS IP only
ss -tan '( dport = :444 )' | awk 'NR>1{print $1, $5}' | sort | uniq -c   # ESTAB, no SYN-SENT
for i in $(seq 1 10); do curl -s -m 10 -x socks5h://127.0.0.1:20170 -o /dev/null -w '%{http_code} ' https://www.google.com; done; echo
```

## Related

- Hotspot boot / TPROXY plumbing: [hotspot-autoboot.md](hotspot-autoboot.md)
- Dashboard: [server-dash.md](server-dash.md)
