# Hotspot Auto-Boot (systemd)

Brings up the `ap0` virtual hotspot (hostapd + dnsmasq + NAT + v2rayA TPROXY
plumbing) automatically on boot. Replaces the manual:

```bash
sudo WAN_IF=enp4s0f1 hotspot-up.sh
```

## Prerequisites

- `/usr/local/sbin/hotspot-up.sh` and `/usr/local/sbin/hotspot-down.sh` installed
  (the hotspot project scripts).
- `hostapd` and `dnsmasq` enabled (`systemctl is-enabled hostapd dnsmasq`).
- `v2raya.service` enabled — hotspot clients are TPROXY'd through it.
- The active WAN interface name. Check with `ip -br -4 addr | grep -v ' lo '`.
  Today it's `enp4s0f1`. If the adapter changes (USB ethernet, different NIC),
  update the `Environment=WAN_IF=` line below.

## Why a custom unit and not just `systemctl enable hostapd`

`hotspot-up.sh` does a bunch of things `hostapd` alone doesn't:

1. Creates the **virtual `ap0` interface** on `phy0` (so wlan0 stays a client).
2. Picks the AP channel to **match wlan0's current channel** (concurrent AP +
   managed on one chip requires same channel), or `AP_CHANNEL` (default `36`)
   when wlan0 is idle, and sets `hw_mode` to match the band. See
   [Wi-Fi band / channel](#wi-fi-band--channel).
3. Sets `ip_forward`, `rp_filter=2`, `accept_local=1` — required for v2rayA's
   TPROXY to deliver hotspot client packets to its local socket.
4. Re-installs v2rayA's fwmark policy route (`ip rule fwmark 0x40/0xc0 table 100`)
   in case something cleared it.
5. Adds the `INPUT -i ap0 ACCEPT` rule that lets TPROXY'd packets through UFW.
6. Adds `MASQUERADE` from `10.42.0.0/24` out the WAN.
7. Restarts `hostapd` + `dnsmasq` in the correct order.

The plain `hostapd.service` is enabled but **fails at boot** without `ap0`
existing — that's expected. Our unit runs after, creates `ap0`, then does
`systemctl reset-failed hostapd && systemctl restart hostapd`.

## Why gate on v2rayA being healthy

Without v2rayA actively listening on its TPROXY ports, hotspot clients get
NAT'd straight out the WAN — bypassing the whole point of the setup. So the
unit waits for `http://127.0.0.1:2017/` to respond before running the script,
not just for `v2raya.service` to be systemd-active (which fires the moment
v2rayA forks, before its API is up).

## Install

Drop this at `/etc/systemd/system/hotspot.service`:

```ini
[Unit]
Description=Bring up ap0 virtual hotspot (hostapd + dnsmasq + NAT)
Documentation=file:/usr/local/sbin/hotspot-up.sh
After=network-online.target sys-subsystem-net-devices-wlan0.device sys-subsystem-net-devices-enp4s0f1.device
Wants=network-online.target sys-subsystem-net-devices-wlan0.device sys-subsystem-net-devices-enp4s0f1.device
After=hostapd.service dnsmasq.service
After=v2raya.service
Wants=v2raya.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=WAN_IF=enp4s0f1
ExecStartPre=/bin/bash -c 'for i in $(seq 1 60); do curl -fsS -o /dev/null --max-time 2 http://127.0.0.1:2017/ && exit 0; sleep 1; done; echo "v2rayA not healthy on :2017 after 60s" >&2; exit 1'
ExecStart=/usr/local/sbin/hotspot-up.sh
ExecStop=/usr/local/sbin/hotspot-down.sh
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

Enable + verify:

```bash
sudo systemd-analyze verify /etc/systemd/system/hotspot.service
sudo systemctl daemon-reload
sudo systemctl enable hotspot.service
```

## Operate

```bash
# Will it run on next boot?
systemctl is-enabled hotspot.service

# Run it now (idempotent, but restarts hostapd → ~3s drop for clients)
sudo systemctl start hotspot.service

# Tear down
sudo systemctl stop hotspot.service

# Logs
journalctl -u hotspot.service -b
```

## Wi-Fi band / channel

Since 2026-10-30 the hotspot runs on **5 GHz, channel 36, 802.11ac at 20 MHz**.
It used to be 2.4 GHz ch 6 / 802.11n / 20 MHz, which capped clients at
65–130 Mbit/s link rate (shared), well below what the v2rayA uplink can push
(~60–200 Mbit/s). After the switch: Mac / iPhone link at 173 Mbit/s
(VHT-MCS 8, 2 streams), Mi-Note-10 at 87 Mbit/s.

Why 20 MHz and not 80: the regulatory domain is `LK` (`iw reg get`), which
only allows 20 MHz on 5170–5250 MHz. Ch 36–48 are the only non-DFS, non-No-IR
5 GHz channels the Intel 8265 will beacon on here.

`/etc/hostapd/hostapd.conf` (relevant lines):

```ini
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
ht_capab=[SHORT-GI-20]
vht_oper_chwidth=0
wmm_enabled=1
country_code=LK
```

`hotspot-up.sh` rewrites `channel=` on every start, so it also has to set the
band — otherwise a 2.4 GHz channel with `hw_mode=a` (or vice versa) makes
hostapd fail and **the hotspot doesn't come up after reboot**. The script now
does:

```bash
CHAN="$(iw dev "$CLIENT_IF" info 2>/dev/null | awk '/channel/ {print $2; exit}')"
[[ -n "${CHAN:-}" ]] || CHAN="${AP_CHANNEL:-36}"
sed -i "s|^channel=.*|channel=$CHAN|" /etc/hostapd/hostapd.conf
# Band follows the channel: 1-14 = 2.4 GHz (g), otherwise 5 GHz (a)
if (( CHAN <= 14 )); then HW_MODE=g; else HW_MODE=a; fi
sed -i "s|^hw_mode=.*|hw_mode=$HW_MODE|" /etc/hostapd/hostapd.conf
```

Check what's live:

```bash
iw dev ap0 info | grep -E 'channel|txpower'
iw dev ap0 station dump | grep -E '^Station|signal:|tx bitrate'
```

### Switch back to 2.4 GHz

For a 2.4 GHz-only device. Set `AP_CHANNEL` with a drop-in (persists across
reboots; delete the drop-in to go back to 36):

```bash
sudo systemctl edit hotspot.service
#   [Service]
#   Environment=AP_CHANNEL=6
sudo systemctl restart hotspot.service    # ~10–20s drop for every client
```

Or restore the pre-5 GHz files (backups left on the box):

```bash
sudo cp -a /etc/hostapd/hostapd.conf.bak-2.4ghz /etc/hostapd/hostapd.conf
sudo cp -a /usr/local/sbin/hotspot-up.sh.bak-2.4ghz /usr/local/sbin/hotspot-up.sh
sudo systemctl restart hotspot.service
```

### Both bands at once? Not on this chip

The Intel 8265 (`phy0`) allows only one AP and one channel at a time:

```
$ iw phy phy0 info | grep -A3 'valid interface combinations'
 * #{ managed } <= 1, #{ AP, P2P-client, P2P-GO } <= 1, #{ P2P-device } <= 1,
   total <= 3, #channels <= 1
```

So 2.4 + 5 GHz simultaneously needs a **second radio**: a USB Wi-Fi adapter
with in-kernel AP-mode support (MediaTek `mt76` family, e.g. MT7612U /
MT7921AU). Plan if/when one is added:

- Run a second hostapd on it (`ap1`) with the **same SSID + passphrase**;
  clients pick the band themselves.
- Bridge `ap0` + `ap1` into one `br-hotspot` holding `10.42.0.1/24`, so
  dnsmasq, NAT, the v2rayA TPROXY rules and the `INPUT -i ... ACCEPT` rule all
  stay single-interface (point them at the bridge instead of `ap0`).
- server-dash reads stations and kicks bans via `iw dev ap0` — it would need
  to iterate both AP interfaces.

## Gotchas

- **WAN_IF is hard-coded.** Re-check it after kernel upgrades or NIC changes
  (predictable interface names can shift). If the WAN moves to a different
  interface, edit `Environment=WAN_IF=` and the two `sys-subsystem-net-devices-...`
  lines, then `daemon-reload`.
- **wlan0 not connected at boot** → script falls back to `AP_CHANNEL`
  (default 36, 5 GHz). Reconnecting wlan0 later does NOT re-channel the AP —
  you'd need to restart the hotspot service.
- **If wlan0 joins a 2.4 GHz network**, the AP is dragged onto that 2.4 GHz
  channel at the next hotspot start (the chip can only be on one channel).
  `hw_mode` follows automatically, so it still comes up — just slower.
- **First-boot race**: `network-online.target` waits for *any* link to be up,
  not necessarily WAN. The `sys-subsystem-net-devices-enp4s0f1.device` ordering
  pin handles the WAN side; the v2rayA health check handles the rest.
- **Stopping the unit drops clients** (runs `hotspot-down.sh`, which kills
  hostapd + dnsmasq). Expected — but don't `systemctl restart` casually.
