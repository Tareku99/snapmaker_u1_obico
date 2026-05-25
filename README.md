# Installing Moonraker-Obico on Snapmaker U1

AI failure detection for your Snapmaker U1 using Obico — works with both the **Obico cloud** (app.obico.io) and a **self-hosted Obico server**.

## Prerequisites

- Snapmaker U1 with **Extended Firmware** installed ([extended firmware site](https://snapmakeru1-extended-firmware.pages.dev/))
- U1 connected to the internet
- An Obico account — either on [app.obico.io](https://app.obico.io) (free tier available) or a self-hosted Obico server
- SSH access to the U1 (enabled via extended firmware)

---

## Quick Install

SSH into your U1 and run:

```bash
curl -fsSL https://raw.githubusercontent.com/D3LZ-D3LZ-D3LZ/u1obico/main/obico-install.sh -o /tmp/obico-install.sh
bash /tmp/obico-install.sh
```

The installer will:
1. Check prerequisites
2. Download moonraker-obico from GitHub
3. Install Python dependencies
4. Prompt you for your Obico server URL
5. Walk you through linking your printer to Obico
6. Set up autostart via a moonraker component
7. Restart moonraker and verify obico is running

---

## What the Installer Does

### Persistence
Enables overlay persistence via `/oem/.debug` so changes survive reboots.

### Autostart
Rather than using systemd (not available on the U1's BusyBox init system), obico is started via a moonraker Python component that triggers when Klipper is ready. This lives in `/home/lava` which persists natively without requiring overlay.

### Webcam
The U1's built-in camera is exposed at `http://127.0.0.1:8080/snapshot.jpg` and `http://127.0.0.1:8080/stream.mjpg` by the extended firmware's custom camera stack. Obico runs in 0.1FPS snapshot mode since Janus is not available — this is sufficient for AI failure detection.

---

## After Installation

- Check your Obico server UI — the printer should appear as **Operational**
- Snapshots update every ~10 seconds when idle, more frequently during prints
- You may see a `Webcam Streaming Failed (Janus)` warning in Obico — this is **normal** and expected. Janus is a WebRTC gateway used for smooth live video streaming and is not available on the U1. Obico automatically falls back to 0.1FPS snapshot mode which is fully sufficient for AI failure detection. You can safely dismiss this notification in Obico.

---

## Uninstall

```bash
bash /tmp/obico-install.sh uninstall
```

---

## Post-Firmware-Upgrade Restore

> ⚠️ Firmware upgrades remove `/oem/.debug` and overlay-persisted changes. The obico source code, config, and moonraker component survive in `/userdata` and `/home/lava`, but ownership and persistence need to be restored.

After a firmware upgrade, run:

```bash
bash /tmp/obico-install.sh restore
```

Or manually:

```bash
touch /oem/.debug
chown -R lava:lava /userdata/moonraker-src
chown -R lava:lava /userdata/obico-logs
/etc/init.d/S61moonraker restart
```

---

## Troubleshooting

**Obico not starting after reboot:**
```bash
ps aux | grep moonraker_obico
tail -f /userdata/obico-logs/moonraker-obico.log
```

**Moonraker component errors:**
```bash
tail -50 /home/lava/printer_data/logs/moonraker.log | grep -i obico
```

**Re-link printer to Obico:**
```bash
cd /userdata/moonraker-src
python3 -m moonraker_obico.link -c moonraker-obico.cfg
```

**No camera image in Obico UI:**

Ensure your Obico server's `HOST_IP` environment variable includes the port, e.g.:
```
HOST_IP=192.168.0.48:3334
```

---

## File Locations

| File | Location |
|---|---|
| Obico source | `/userdata/moonraker-src/` |
| Obico config | `/userdata/moonraker-src/moonraker-obico.cfg` |
| Obico logs | `/userdata/obico-logs/moonraker-obico.log` |
| Moonraker component | `/home/lava/moonraker/moonraker/components/obico_starter.py` |
| Moonraker config fragment | `/home/lava/printer_data/config/extended/moonraker/05_obico.cfg` |
