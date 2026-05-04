# kniferoll v2 — HA Satellite Stack Design

Companion document to `V2_PLAN.md`. Detailed specification for the Pi-flavored Home Assistant satellite stack capability. The orchestration substrate lives in the **kniferoll-unpack** coordination repo (per `V2_PLAN.md` §5b); the per-role install scripts live in **kniferoll-linux-deb** and **kniferoll-linux-arch** (and their managed-* twins, where corp-aware variants make sense).

This doc is referenced from `V2_PLAN.md` §5d.

---

## 1. Context and scope

Home Assistant runs on `hyp-pve-02`, one of two Proxmox nodes. A Pi 4 (aarch64) sits on the Tailscale mesh as a separate physical box. v2 treats the Pi as an **HA satellite endpoint**, not as a control plane — the brain stays at hyp-pve-02; the Pi runs services that feed HA over Tailscale or LAN.

This replaces the earlier "Pi media stack" framing in `V2_PLAN.md` §5d (where the Pi was assumed to be the brain). The §5d framing is updated in V2_PLAN.md proper to point here.

Per-OS scope: this stack is spec'd for **Linux Debian/Ubuntu and Linux Arch**. macOS and Windows machines are not satellite hardware in this fleet — they're HA *clients* (Companion app via brew/winget), which is a different capability category and out of scope for this document.

---

## 2. The "HA satellite" capability category

A new TUI category in the `kniferoll-unpack` selector (added to `V2_PLAN.md` §6b.1's category table). Sits alongside the Tailscale capability (`V2_PLAN.md` §5c). The category is **Linux-only** — on `kniferoll-mac` and `kniferoll-windows` the row is absent from the TUI entirely (not greyed out — absent), since the underlying service shapes don't apply.

### 2.1 Gating

The HA satellite category is enabled in the TUI only when **at least one** of the following is true:

- The Tailscale row is selected in the same run, or Tailscale is already installed on the host (`command -v tailscale` returns success and `tailscale status` shows authenticated).
- The user has explicitly passed `--ha-host LAN_HOST_OR_IP` indicating direct LAN reachability to the HA host.

When neither condition holds, the HA satellite rows render dim/grey with a `[needs tailscale or --ha-host]` suffix and are non-selectable. Toggling Tailscale on, or supplying the `--ha-host` flag, enables them.

### 2.2 Multi-select within

Each role in the role catalog (§4) is an individual checkbox. The user picks any subset for this Pi (or any Linux box). Default state per role is set in §4 — first-wave roles (MPD, BT Proxy) default to ON when the category is enabled; opt-in roles (Z2M, Wyoming) default to OFF; out-of-scope roles aren't shown.

---

## 3. Inputs collected up front

When the HA satellite category is selected, the unpack flow collects these inputs *before* installing any role. Collecting up front avoids mid-install prompts, which interrupt the side-by-side log display (`V2_PLAN.md` §6b.8) and produce a worse UX.

| Input | Default | Notes |
|-------|---------|-------|
| **HA URL** | (no default; required) | E.g. `http://hyp-pve-02:8123` for LAN, `http://hyp-pve-02.tailXXXX.ts.net:8123` for Tailscale. The flow validates reachability with a `curl -s -o /dev/null -w '%{http_code}' <URL>/api/` and refuses to proceed if HA isn't reachable from this host. |
| **HA long-lived access token** | (no default; required) | The flow prints click-by-click instructions: HA UI → Profile → Long-Lived Access Tokens → Create. The token is stored at `~/.config/kniferoll/ha-token` with mode 0600 and used for subsequent role-integration verifications. Never logged. |
| **Network mode** | Tailscale-only when Tailscale is selected; LAN-wide otherwise | Three options: (a) bind to Tailscale interface only — most secure; (b) bind to LAN — simpler, larger attack surface; (c) bind to both. Each role's config takes the resolved mode and applies it (e.g., MPD's `bind_to_address`). |
| **Sudo password** | Cached up front, refreshed by background `sudo -v` keepalive | Same pattern the in-flight Linux hotfix establishes; the satellite flow doesn't reinvent it. The keepalive PID is tracked and torn down by `st_cleanup` (per `lib/split_terminal.sh`). |

The HA URL and access token together form the **HA endpoint context**. They're cached at `~/.config/kniferoll/ha-endpoint.json` (mode 0600) so re-runs of the unpack flow on the same machine don't re-prompt.

---

## 4. Role catalog

The canonical satellite roles v2 ships with. Status markers reflect Chef's final scoping calls:

- **DEFAULT-ON** — installed when the HA satellite category is selected, unless the user explicitly unchecks the row.
- **AVAILABLE-OFF** — visible in the TUI, defaulted unchecked, opt-in by the user.
- **OUT OF SCOPE** — explicitly not shipped on Pi targets in v2; rationale and alternative documented.

### 4.1 MPD media endpoint — DEFAULT ON

**What it does in HA satellite context.** Runs Music Player Daemon on the Pi, serves music from a local library or NAS mount, exposes itself to HA via HA's `mpd` integration. HA's media player card can then control the Pi's playback from any HA client (web, mobile app, voice).

**Install method.** `sudo apt install mpd mpc` on Debian/Ubuntu, `sudo pacman -S mpd mpc` on Arch. Both ship as well-maintained native packages; no cargo/pip/binary-release dance.

**Minimum version for the documented config schema.** `mpd >= 0.21` (for the `audio_output { type "alsa" ... }` semantics and the `bind_to_address` / `port` syntax used below). Bookworm and newer Ubuntu LTS ship 0.23+; Arch is on the latest. If a host's apt repo serves an older version, the install script refuses with a clear "this script needs mpd ≥ 0.21; your distro has X.Y.Z — upgrade your apt sources or use a backports repo" message rather than writing config the daemon will reject.

**Config file.** `/etc/mpd.conf` — the script writes a kniferoll-managed marker block (per `V2_PLAN.md` §1.8 sweep pattern) containing:

```
# BEGIN kniferoll mpd
music_directory     "<MUSIC_LIB_PATH>"      # prompt: default ~/Music
playlist_directory  "/var/lib/mpd/playlists"
db_file             "/var/lib/mpd/database"
log_file            "/var/log/mpd/mpd.log"
state_file          "/var/lib/mpd/state"
sticker_file        "/var/lib/mpd/sticker.sql"
bind_to_address     "<NET_BIND>"            # Tailscale interface or 0.0.0.0 per network mode
port                "6600"
audio_output {
    type    "alsa"
    name    "Local ALSA"
    device  "default"
    mixer_type "software"
}
# END kniferoll mpd
```

The path prompts: `<MUSIC_LIB_PATH>` defaults to `~/Music` (creates the dir if missing); user can override. `<NET_BIND>` resolves from §3 Network mode — the Tailscale interface IP (read from `tailscale status --json | jq -r '.Self.TailscaleIPs[0]'`) or `0.0.0.0` for LAN-wide.

**Systemd unit.** Ships with the apt/pacman package. Script enables and starts: `sudo systemctl enable --now mpd`.

**Idempotency contract.** Re-runs detect existing kniferoll marker block in `/etc/mpd.conf` and replace it idempotently. Music library path prompt is skipped on re-run (the existing path is honored unless the user passes `--reconfigure`). Service is restarted only if the config block actually changed (`cmp -s` guard, same pattern as the rc-block sweep).

**Post-install verification.** `nc -zv <bind_ip> 6600` to confirm the daemon is listening; `mpc -h <bind_ip> ping` to confirm it responds; `mpc -h <bind_ip> stats` to print the indexed track count (sanity check for the music library path).

**HA-side integration.** Printed in the next-steps banner (§5):

```
[HA] Add MPD to Home Assistant:
     1. Open HA: <HA_URL>/config/integrations
     2. Click "+ Add Integration", search "Music Player Daemon"
     3. Host:     <PI_TAILSCALE_OR_LAN_IP>
        Port:     6600
        Password: (leave blank)
     4. Submit. The Pi's library appears as a media_player.<name> entity.
```

### 4.2 Bluetooth Proxy via ESPHome — DEFAULT ON

**What it does in HA satellite context.** Runs ESPHome's Bluetooth Proxy as a small process on the Pi; advertises itself via mDNS so HA discovers it; HA then uses the Pi as a remote BLE host, extending HA's Bluetooth reach to wherever the Pi physically lives. Cheap, well-documented, clean separation from HA itself.

The recommended path is ESPHome's BT Proxy because it's the cleaner architecture: ESPHome is purpose-built for this, ships maintained YAML templates, and HA discovers it natively. The alternative (`bluez` + `home_assistant_bluetooth` proxy) is more general but requires more glue and has a worse maintenance story for this specific use case.

**Install method.** `pip install esphome` inside a dedicated venv at `/opt/kniferoll/venv-esphome` (NOT the system Python). The venv approach isolates ESPHome's dependency tree from the host Python. `apt install python3-venv` is a prerequisite (added to the script's preflight if missing).

**Minimum version for the documented YAML schema.** `esphome >= 2024.6` (for `bluetooth_proxy:` block + `platform: linux` / `board: linux` host-target support). The pip install pins to a specific version per the §6.2 cooling-off rule; the pinned version is recorded in `kniferoll-unpack/lib/inventory/satellite.sh` alongside the role's other metadata. Re-runs upgrade only when the pin advances.

**Config file.** `/etc/kniferoll/esphome-btproxy.yaml`, generated from a template:

```yaml
esphome:
  name: pi-bt-proxy
  platform: linux
  board: linux

api:
  encryption:
    key: "<GENERATED_RANDOM_BASE64>"   # 32-byte key, generated once and cached

ota:
  platform: esphome

bluetooth_proxy:
  active: true

logger:
  level: INFO
```

The encryption key is generated once with `openssl rand -base64 32`, written to `/etc/kniferoll/esphome-btproxy.key` mode 0600, and referenced in the YAML. Re-runs reuse the cached key (so HA doesn't re-pair).

**Systemd unit.** `/etc/systemd/system/kniferoll-esphome-btproxy.service`:

```ini
[Unit]
Description=kniferoll ESPHome Bluetooth Proxy
After=network-online.target bluetooth.target
Wants=network-online.target
Requires=bluetooth.target

[Service]
Type=simple
ExecStart=/opt/kniferoll/venv-esphome/bin/esphome run /etc/kniferoll/esphome-btproxy.yaml --no-logs
Restart=on-failure
RestartSec=5
User=root
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW

[Install]
WantedBy=multi-user.target
```

**Idempotency contract.** Re-runs detect the existing venv and reuse it (`pip install --upgrade esphome` if a newer pinned version is in the inventory; otherwise no-op). The encryption key is reused from the cached file. The systemd unit file is rewritten idempotently from the template.

**Post-install verification.** `systemctl is-active kniferoll-esphome-btproxy` returns `active`; `avahi-browse -t _esphomelib._tcp` finds the proxy advertising on mDNS.

**HA-side integration.** Banner copy:

```
[HA] Bluetooth Proxy auto-discovers on the same network. If it doesn't:
     1. HA UI → Settings → Devices & Services → "+ Add Integration"
     2. Search "ESPHome", select it
     3. Host:    <PI_TAILSCALE_OR_LAN_IP>
        Port:    6053
        Encryption key: (read from /etc/kniferoll/esphome-btproxy.key on the Pi)
     4. Submit. BLE devices in range of the Pi now show up in HA's
        Bluetooth integration.
```

### 4.3 Zigbee2MQTT — AVAILABLE-OFF

**What it does.** Runs Z2M bridging a Zigbee USB stick to MQTT; HA picks up the devices via its MQTT integration with auto-discovery. Out of the first-wave default because it requires a Zigbee USB stick (Sonoff ZBDongle-P, ConBee II, etc.) that Chef hasn't confirmed present; surfacing it in the TUI as default-on would result in install-time failures on Pis without the hardware.

**Install method.** Install via apt where available (Debian 12+ `apt install zigbee2mqtt`); else from npm into `/opt/kniferoll/z2m`. Apt is preferred when available because the package is signed and tracked by the distro. Npm install path fetches `zigbee2mqtt` at a pinned version, runs `npm ci` to lock the dependency tree, no curl-pipe-bash anywhere.

**Minimum version for the documented configuration.** `zigbee2mqtt >= 1.30` (for HA-discovery v2 schema + the `homeassistant: true` shorthand used in the config below). The apt path on older distros may serve a back-ported version that's pre-1.30; in that case the install script falls back to the npm-pinned path. Co-installed mosquitto: any 2.x version (the broker side of the protocol is stable and `mosquitto >= 2.0` is in every supported distro's apt/pacman as of 2026).

**Preflight check.** Before installing, the script enumerates serial devices (`ls /dev/serial/by-id/` and `ls /dev/ttyUSB*`) and refuses to proceed if no plausible Zigbee adapter is found. The user can override with `--force-no-stick` (e.g., they're installing in advance of plugging the stick in).

**Config file.** `/opt/kniferoll/z2m/data/configuration.yaml`:

```yaml
homeassistant: true
permit_join: false           # security: never default-on; user opens the join window manually from HA
mqtt:
  base_topic: zigbee2mqtt
  server: mqtt://localhost:1883
serial:
  port: <PROMPTED_SERIAL_PATH>    # default /dev/ttyUSB0; prompt confirms
frontend:
  port: 8080
  host: <NET_BIND>
advanced:
  network_key: GENERATE       # Z2M generates and caches on first run
  pan_id: GENERATE
  ext_pan_id: GENERATE
  log_level: info
```

**Co-installed dependency: MQTT broker.** Z2M needs an MQTT broker. The script installs `mosquitto` (via apt/pacman) on the same Pi by default; surfaces a sub-toggle "use existing MQTT broker (advanced)" for users with a remote broker (which prompts for the broker URL).

**Systemd unit.** Standard ExecStart pointing at `/opt/kniferoll/z2m/index.js` via Node, or just `systemctl enable --now zigbee2mqtt` when the apt path was used. Mosquitto's unit is the distro default.

**Idempotency contract.** Re-runs detect the existing config and refuse to overwrite the `network_key` / `pan_id` / `ext_pan_id` (overwriting these would orphan paired devices). All other config keys are idempotently rewritten.

**Post-install verification.** `nc -zv localhost 1883` (mosquitto); `nc -zv <bind_ip> 8080` (Z2M frontend); `mosquitto_sub -h localhost -t 'zigbee2mqtt/bridge/info' -C 1` shows Z2M's bridge info.

**HA-side integration.** Banner copy:

```
[HA] Zigbee2MQTT integrates via MQTT discovery:
     1. HA UI → Settings → Devices & Services → "+ Add Integration"
     2. Search "MQTT", configure the broker:
        Host: <PI_TAILSCALE_OR_LAN_IP>   Port: 1883
     3. Z2M devices auto-appear under MQTT.
     4. Z2M frontend (for joining new devices) at:
        http://<PI_IP>:8080
```

### 4.4 Wyoming voice satellite — AVAILABLE-OFF

**What it does.** Runs the Wyoming voice-satellite protocol; HA's Voice Assist points at it and the Pi becomes a "speak/listen" endpoint near wherever the Pi physically lives. Out of the first-wave default because mic/speaker hardware varies widely (USB mic, HAT mic, no mic at all) and Voice Assist setup downstream in HA is its own configuration project.

**Install method.** `pip install wyoming-satellite` inside a dedicated venv at `/opt/kniferoll/venv-wyoming`. Python 3.11+ required; preflight verifies the host Python version.

**Minimum version for the documented systemd ExecStart args.** `wyoming-satellite >= 1.4` (for the `--snd-command` / `--mic-command` arg shape and the `--uri tcp://...:10700` form). Pinned via the cooling-off rule; recorded in `kniferoll-unpack/lib/inventory/satellite.sh`. Older versions used different flag names (`--audio-input` / `--audio-output`); the install script honors the pinned version, and a runtime version check inside the systemd unit's ExecStart wrapper would be overengineering for a venv-pinned tool.

**Hardware enumeration.** Before installing, the script lists available capture and playback devices via `arecord -l` (capture) and `aplay -l` (playback) and prompts the user to pick one of each. The picks are stored in the systemd unit's `ExecStart` args. Users with no capture device can pick `none` to install but disable the listening side; the satellite then becomes speaker-only.

**Config / systemd unit.** No standalone config file; everything goes into the systemd ExecStart args:

```ini
[Service]
Type=simple
ExecStart=/opt/kniferoll/venv-wyoming/bin/python3 -m wyoming_satellite \
    --name "kniferoll-pi-satellite" \
    --uri tcp://<NET_BIND>:10700 \
    --mic-command 'arecord -D <CAPTURE_DEVICE> -r 16000 -c 1 -f S16_LE -t raw' \
    --snd-command 'aplay -D <PLAYBACK_DEVICE> -r 22050 -c 1 -f S16_LE -t raw'
Restart=on-failure
RestartSec=5
```

**Idempotency contract.** Re-runs reuse the venv. The systemd unit is rewritten if the prompted device choices have changed; restart only happens if the unit file content actually differs.

**Post-install verification.** `nc -zv <bind_ip> 10700`; `systemctl is-active kniferoll-wyoming-satellite`; a one-shot loopback test that records 1 second from the mic and replays it through the speaker (skipped if the user picked `none` for either).

**HA-side integration.** Banner copy:

```
[HA] Wyoming satellite integrates via HA's Voice Assist:
     1. HA UI → Settings → Voice Assistants
     2. Add Wyoming Protocol Satellite:
        Host: <PI_TAILSCALE_OR_LAN_IP>   Port: 10700
     3. Configure your assistant pipeline (STT, intent, TTS) in HA.
        See https://www.home-assistant.io/voice_control/
```

### 4.5 Frigate NVR — OUT OF SCOPE on Pi

**Decision.** Not shipped as a Pi-targetable role in v2.

**Rationale.** Frigate runs object-detection inference on every camera frame. On a Pi 4 the inference is the bottleneck; without a Coral USB accelerator the experience is poor (frame drops, latency spikes, thermal throttling). Even with a Coral, the install footprint (Docker + Compose + Frigate's image + camera RTSP plumbing + USB power budget for the Coral alongside other satellite USB devices) makes the Pi a bad fit for a v2-supported install profile.

**Recommended alternative.** Frigate runs on `hyp-pve-02` (the existing Proxmox node hosting HA) when NVR enters scope. The v2 satellite spec does not include a hyp-pve-02 install path because hyp-pve-02 is provisioned separately from the per-machine kniferoll flow. A future `kniferoll-proxmox` capability (out of v2.0 scope) could spec the Frigate-on-Proxmox install if Chef wants it.

**Plan posture.** The TUI does not show Frigate as a row on `kniferoll-linux-deb` / `kniferoll-linux-arch` v2.0. The README mentions Frigate-on-hyp-pve-02 in a "future / not on Pi" callout for users who go looking.

### 4.6 ESPresense — OUT OF SCOPE on Pi (wrong hardware)

**Decision.** Not a Pi role. ESPresense runs on ESP32 hardware, not on a Linux SBC. Re-confirming the call from the earlier brief.

**Recommended alternative.** Room-presence detection on a Pi-flavored fleet is best handled by the §4.2 Bluetooth Proxy feeding HA's native presence inference (via the `bermuda` HACS integration or HA's built-in Bluetooth tracking). The Pi reports BLE observations; HA does the math.

**Plan posture.** ESPresense is not in the §4 catalog. The README's "future / not on Pi" callout mentions it for users wondering why it's absent, with the bermuda alternative pointed at.

---

## 5. The "next steps" banner

After a satellite install run completes, the unpack flow prints a single, well-formatted banner. Box-bordered per `docs/FLAVOR.md`'s security-decision framing. Layout:

```
╭──────────────────────────────────────────────────────────────────╮
│            kniferoll satellite install — next steps              │
╰──────────────────────────────────────────────────────────────────╯

  Roles installed on this Pi:
    [✓] MPD media endpoint        (port 6600)
    [✓] Bluetooth Proxy (ESPHome) (port 6053)
    [ ] Zigbee2MQTT               (not selected)
    [ ] Wyoming voice satellite   (not selected)

  HA-side actions required:

  ── MPD ──────────────────────────────────────────────────────────
  1. Open HA: http://hyp-pve-02:8123/config/integrations
  2. Click "+ Add Integration", search "Music Player Daemon"
  3. Host: 100.X.X.X (Pi tailnet IP)   Port: 6600   Password: blank
  4. Submit.

  ── Bluetooth Proxy ──────────────────────────────────────────────
  Auto-discovers via mDNS. If not visible in HA within 60s:
  1. HA UI → Settings → Devices & Services → "+ Add Integration"
  2. Search "ESPHome"
  3. Host: 100.X.X.X   Port: 6053
     Encryption key: <printed inline>
  4. Submit.

  Verification commands you can run from your laptop (over Tailscale):

    nc -zv 100.X.X.X 6600          # MPD listening?
    nc -zv 100.X.X.X 6053          # ESPHome BT Proxy listening?
    mpc -h 100.X.X.X stats         # MPD library indexed correctly?

  Files of interest on this Pi:
    /etc/mpd.conf                              MPD config (edit + restart mpd)
    /etc/kniferoll/esphome-btproxy.yaml        BT Proxy config
    /etc/kniferoll/esphome-btproxy.key         BT Proxy encryption key (mode 0600)
    ~/.kniferoll/logs/<repo>-<ts>.log          Install log

  If anything's not working, re-run:
    ./install.sh --check                        State drift report
    ./install.sh --reconfigure ha-satellite     Re-prompt for inputs

  Knives sharp. Out.
```

Implementation: the banner is built incrementally during the install run — each role's installer appends its lines to a temp file at `/tmp/kniferoll-banner-<pid>` — and printed atomically at the end. Roles that failed install print their lines under a `Roles that did NOT install:` section with the failure cause inline.

---

## 6. Idempotency contract for satellite roles

Re-running the unpack flow on a Pi that already has roles installed must:

1. **Detect existing installs.** Check for the role's daemon binary (`command -v mpd`, `command -v esphome`), its systemd unit, and its config file. Mark the role as already-installed in the run plan.
2. **Prompt before overwriting configs (default: no).** If the kniferoll marker block in `/etc/mpd.conf` is present and unchanged from the last run's hash (recorded in `~/.kniferoll/state.json`), skip the rewrite silently. If the block is present but modified (user has edited it manually, or a config-template version bump is pending), prompt: `Existing config differs. Overwrite? [y/N]` — default no. The user's manual edits are precious.
3. **Append, don't replace.** Where the role's config supports an `include` directive, prefer adding a kniferoll-managed include file rather than rewriting the upstream config. (MPD doesn't support includes; Z2M does; ESPHome's main YAML doesn't but the satellite YAML is fully kniferoll-owned.)
4. **Re-verify HA-side reachability.** Even on a "nothing to do" re-run, the flow runs the post-install verification suite (§4 per role) and reports the verified-vs-trusted status. If verification regressed (port stopped listening, mDNS stopped advertising), the role is flagged for the user with a remediation suggestion.
5. **Re-print the next-steps banner.** Always. Idempotent re-runs include a banner that says "everything is still good" — useful when the user runs the script a week later and wants to remember the HA URL or the encryption key path.

The marker-block pattern (per `V2_PLAN.md` §1.8 sweep) applies to every config file the script writes:

```
# BEGIN kniferoll <role>
# (kniferoll-managed; manual edits below this line will be preserved on re-run
#  as long as they don't conflict with the managed lines above)
...
# END kniferoll <role>
```

The AWK sweep parser (subtreed from `kniferoll-unpack/lib/`) handles these the same way it handles `~/.zshrc`'s Zscaler block — strip and re-write the kniferoll-owned region; preserve everything outside it.

---

## 7. Per-OS scope and cross-layer architecture

### 7.1 Per-OS scope

| Repo | Satellite roles | Why |
|------|-----------------|-----|
| `kniferoll-linux-deb` | All §4 default-on + available-off roles | Primary Pi target (Raspberry Pi OS, Ubuntu Server). |
| `kniferoll-linux-arch` | All §4 default-on + available-off roles | Arch on Pi is uncommon but supported (CachyOS-on-Pi exists). |
| `kniferoll-managed-linux-deb` | All §4 roles + corp-aware variants where the role makes outbound HTTP (HA URL might be behind corp DNS, etc.) | Corp Pi satellites are rare but possible. First cut: same install logic, with the corp-CA env-var fan-out applied to any role that does outbound HTTP at install time. |
| `kniferoll-managed-linux-arch` | Same as managed-deb | Same caveats. |
| `kniferoll-mac` / `kniferoll-managed-mac` | None | Mac isn't a satellite host in this fleet. Mac may install the HA Companion app via brew, but that's a different capability category (HA *clients*, not satellite roles). |
| `kniferoll-windows` / `kniferoll-managed-windows` | None | Same as Mac. HA Companion via winget, not a satellite role. |
| `kniferoll-wsl2` / `kniferoll-managed-wsl2` | None | WSL2 isn't a satellite-host shape. The user's Windows host might be a satellite via a separate `kniferoll-windows-satellite` capability someday; not in v2. |

### 7.2 Cross-layer architecture

The satellite stack lives across two layers:

- **`kniferoll-unpack` (public coordination repo).** Owns:
  - The HA satellite TUI category and the role-row rendering.
  - The §3 input-collection flow (HA URL, token, network mode, sudo).
  - The role-orchestration logic — the order of role installs, dependency resolution (e.g., Z2M needs mosquitto first), failure aggregation.
  - The §5 next-steps banner template.
  - The idempotency contract enforcement (marker block pattern, hash-based change detection, the verified-vs-trusted summary).
  - The HA-endpoint context cache (`~/.config/kniferoll/ha-endpoint.json`).

- **`kniferoll-linux-deb` and `kniferoll-linux-arch` (per-OS public repos).** Own:
  - The per-role install scripts: `lib/satellite/mpd.sh`, `lib/satellite/btproxy.sh`, `lib/satellite/z2m.sh`, `lib/satellite/wyoming.sh`. Each is independently callable (e.g., for the migrate subcommand or for partial reinstall).
  - The Debian/Arch package-manager specifics (apt vs pacman command lines, package-name differences, AUR fallbacks where applicable).
  - The systemd unit templates per role.
  - The hardware-enumeration helpers (Zigbee stick detection, audio device listing).

The `-managed-*` repos add corp-CA propagation around any role that makes outbound HTTP calls, but otherwise reuse the unmanaged role scripts via the §5b subtree. **First-cut managed satellite scope: same install logic, with the corp-CA env-var fan-out (§6.2) applied where roles do install-time HTTP. Future-work TODO.**

---

## 8. Verification audit pattern

Every role's install ends with a "verified vs trusted" two-column report, matching the pattern the in-flight Linux hotfix is establishing. The format:

```
  Role: MPD
  ├─ Daemon binary:        verified  (mpd 0.24.0)
  ├─ Service active:       verified  (systemctl is-active mpd)
  ├─ Listening on 6600:    verified  (nc -zv 100.X.X.X 6600)
  ├─ Library indexed:      verified  (mpc stats: 1247 tracks)
  └─ HA reachability:      trusted   (HA URL responds; integration not yet added)
```

`verified` = the install script ran a positive test that returned the expected result. `trusted` = the install script set up the precondition but cannot directly verify (e.g., HA-side integration is the user's manual step). The banner aggregates per-role audits into one block and flags anything not `verified` for the user's attention.

The audit data is also written to `~/.kniferoll/state.json` under a `satellite_roles.<role>.verification` key so subsequent `--check` runs can compare against the prior audit and report drift.

---

## 9. Pi-specific concerns

The Pi target has a few hardware realities that bite if ignored. v2 codifies sensible defaults for them.

### 9.1 aarch64 binary availability

Some upstreams (mostly cargo crates and binary releases on GitHub) ship x86_64-only artifacts. The role catalog is curated to favor packages with native arm64 support:

- MPD: native apt/pacman package, arm64-tested.
- ESPHome: pip wheel ships pure-Python or has arm64 wheels for compiled deps; verified at install time.
- Z2M: npm package with arm64-compatible deps; prebuilt zigbee-herdsman binaries cover arm64.
- Wyoming-satellite: pure Python; arm64 is fine.

When a future role lands without arm64 support, the install script preflight detects the missing binary and refuses with a clear "this role isn't currently arm64-compatible" message. Better to refuse loudly than to half-install something that won't run.

### 9.2 SD card lifespan

A satellite Pi running mosquitto, MPD, and ESPHome writes a steady trickle of logs that will burn an SD card over months/years. The "RPi-flavored install profile" (§9.4) defaults `/var/log` to a tmpfs mount and installs `log2ram` so logs accumulate in RAM during runtime and flush to disk only at shutdown.

`log2ram` is installed via apt on Debian/Ubuntu (third-party repo: `azlux.fr/repo` — added with the same proper-key pattern as Tailscale per §5c.3, **not** curl-pipe-bash). On Arch it's available in the AUR. Default size: 128MB tmpfs.

### 9.3 USB power budget

A Pi 4 supplies ~1.2A across all USB ports combined under the official 5V/3A power supply. A typical satellite stack — Zigbee USB stick (~50mA), USB audio interface (~200mA), plus an opt-in Coral (~900mA peak) — can overrun this budget under load and produce undervoltage symptoms (random reboots, USB device dropouts, file system corruption).

The script doesn't enforce a powered hub but prints a recommendation in the next-steps banner whenever ≥2 USB devices are detected during install:

```
[!] USB power note:
    Detected <N> USB devices on this Pi. The Pi's onboard USB power
    is limited; for reliable operation with multiple satellite
    peripherals, a powered USB hub is recommended.
```

### 9.4 RPi-flavored install profile

When the install script detects it's running on Pi hardware (`/proc/cpuinfo` contains `Raspberry Pi`), the satellite category enables a **Pi-flavored profile** by default (sub-toggle: ON), which turns on:

- `log2ram` install + tmpfs `/var/log` mount.
- A daily cron'd `journalctl --vacuum-time=7d` to keep journal size bounded.
- `dphys-swapfile` config tuned to 0 (no swap on SD; the Pi has 4-8GB RAM and swap-to-SD destroys the card for marginal gain).
- The §9.3 USB power banner.

The profile is its own checkbox; advanced users on Pi can uncheck it if they have a different opinion (e.g., they're booting from USB SSD and don't care about SD lifespan).

---

## 10. Out of scope / deferred to v2.1+

### 10.1 Multi-Pi orchestration

v2.0 ships **one-machine-at-a-time only.** The user runs the unpack flow on each Pi separately. No fleet-wide "install MPD on all my Pis from one machine via Tailscale + SSH" capability.

This is a deliberate scope cut. Multi-Pi orchestration adds substantial complexity (SSH key management, target inventory file, partial-failure handling across N hosts, transactional rollback semantics) for a use case Chef hasn't yet — single Pi today. Note as a v2.1+ enhancement when the second Pi enters the fleet, designed against real cardinality rather than against "what if there are many."

### 10.2 Frigate NVR on Pi

Out per §4.5. Recommended host is `hyp-pve-02`. A future `kniferoll-proxmox` capability (out of v2.0 scope) could spec the Frigate-on-Proxmox install if Chef wants it.

### 10.3 ESPresense

Out per §4.6. Wrong hardware target (ESP32, not Pi). Adjacent functionality is achievable via §4.2 Bluetooth Proxy + HA's bermuda HACS integration.

### 10.4 First-cut managed satellite limitations

The `-managed-*` satellite implementations in v2.0 reuse the unmanaged role scripts with corp-CA env-var fan-out applied. Future work: corp-policy-aware role variants where a role behaves differently in a managed vs unmanaged context (e.g., MQTT broker behind corp auth, HA-token rotation policies, internal mirror substitution for npm/pip role-install paths). Out of v2.0 scope.

---

## Cross-reference index

- `V2_PLAN.md` §5b — kniferoll-unpack coordination layer (parent context)
- `V2_PLAN.md` §5c — Tailscale capability (this stack's network substrate)
- `V2_PLAN.md` §5d — pointer to this document
- `V2_PLAN.md` §6.2 — security manifesto (no curl-pipe-bash, cooling-off, deferred-replacement)
- `V2_PLAN.md` §6b.1 — TUI category table including the HA satellite row
- `V2_PLAN.md` §6b.7 — AI tools category (parallel pattern: dense per-tool table with TUI descriptions)
- `V2_PLAN.md` §6b.8 — side-by-side live log display (the satellite next-steps banner runs after `st_cleanup`)
- `V2_PLAN.md` §11 — pedagogy (each role install is required to ship a `docs/deep-dives/satellite-<role>.md`)
