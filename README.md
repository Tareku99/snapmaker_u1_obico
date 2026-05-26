# 🚀 Obico for Snapmaker U1 (Extended Firmware)

AI‑powered print monitoring and failure detection for the **Snapmaker U1**, using **Moonraker‑Obico** and the **Paxx Extended Firmware**.

This installer automatically:

- Fetches the latest Obico source (master branch)
- Installs it inside a Python virtual environment
- Creates a **self‑healing Moonraker autostart component**
- Enables **MJPEG streaming** (fastest internal camera mode)
- Falls back to snapshot mode if MJPEG is unavailable
- Links your printer to Obico (Cloud or Self‑Hosted)
- Automatically restores itself after firmware updates
- Repairs permissions and persistence on boot
- Provides update, backup, and health‑check tools

---

# 📦 Requirements

- **Snapmaker U1 running Paxx Extended Firmware**  
  https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware
- **SSH access enabled**
- **Internet connection**
- **Obico account**  
  - Obico Cloud → https://app.obico.io  
  - Self‑Hosted Obico → any custom server URL
- Basic terminal familiarity

---

# ⚡ Installation Steps

SSH into your Snapmaker U1 and run:

### 1. Download the installer
```bash
curl -fsSL "https://raw.githubusercontent.com/Tareku99/snapmaker_u1_obico/main/obico-install.sh?$(date +%s)" -o /tmp/obico-install.sh
```

### 2. Run the installer
```bash
bash /tmp/obico-install.sh install
```

The installer will:

- Verify extended firmware  
- Enable persistence  
- Fetch the latest Obico source  
- Install into `/userdata/obico-venv`  
- Create config + logs  
- Link your printer (unless `--no-link` is used)  
- Install a **self‑healing autostart component**  
- Restart Moonraker  
- Confirm Obico is running  

---

# 🌐 Obico Cloud vs Self‑Hosted Obico

### Obico Cloud (default)
- URL: `https://app.obico.io`
- Easiest setup

### Self‑Hosted Obico
Fully supported.

During installation you will be prompted:

```
Choose your Obico server type:
  1) Obico Cloud
  2) Self-Hosted Obico
```

Enter your server URL, for example:

```
http://192.168.1.69:3334
https://obico.mydomain.com
```

---

# 🧠 How It Works

## Virtual Environment
All Python dependencies are installed into:

```
/userdata/obico-venv
```

This prevents conflicts with system Python and survives firmware updates.

## Persistent Directories
The installer uses:

```
/userdata/moonraker-src        (Obico source)
/userdata/obico-logs           (logs)
/userdata/obico-venv           (Python venv)
/userdata/obico-backup         (backups)
/userdata/obico-version.cfg    (installer + version metadata)
```

Everything is isolated and safe across reboots.

## Self‑Healing Autostart Component
A Moonraker component is created at:

```
/home/lava/moonraker/moonraker/components/obico_starter.py
```

And enabled via:

```
/home/lava/printer_data/config/extended/moonraker/05_obico.cfg
```

On every boot, it automatically:

- Re‑enables persistence if wiped by firmware update  
- Fixes permissions  
- Ensures Obico starts cleanly  

This makes the installation **self‑healing**.

---

# 📷 Webcam Support (MJPEG Streaming Enabled)

Paxx Extended Firmware exposes the internal camera at:

```
http://<printer-ip>/webcam/stream.mjpg   (MJPEG stream)
http://<printer-ip>/webcam/snapshot.jpg  (snapshot fallback)
```

The installer automatically:

- Detects your printer’s LAN IP  
- Sets MJPEG as the **primary** stream  
- Enables snapshot as fallback  
- Configures Obico for the fastest possible internal camera mode  

No Janus/WebRTC is required or supported on the U1.

---

# 📝 Configuration File

Created at:

```
/userdata/moonraker-src/moonraker-obico.cfg
```

Includes:

- Obico server URL (Cloud or Self‑Hosted)
- Moonraker host/port  
- Webcam MJPEG + snapshot URLs  
- Logging path  

---

# 🔗 Linking Your Printer

During installation, you will be prompted to link your printer using:

```
moonraker_obico.link
```

If you prefer to link later:

```bash
bash obico-install.sh install --no-link
```

---

# 🔄 Automatic Restore After Firmware Updates

Paxx firmware updates wipe overlay persistence.

This installer now includes **full auto‑restore**:

### ✔ Auto‑restore during install  
### ✔ Auto‑restore on boot  
### ✔ Auto‑restore after updates  
### ✔ Auto‑repair of permissions  
### ✔ No user action required  

Your Obico install remains intact automatically.

---

# 🗑️ Uninstall

```bash
bash obico-install.sh uninstall
```

Removes:

- venv  
- source directory  
- logs  
- autostart component  
- Moonraker config entry  

Then restarts Moonraker.

Keep config + logs:

```bash
bash obico-install.sh uninstall --keep-config
```

---

# 🧪 Advanced Usage

## Install a specific Obico version
```bash
bash obico-install.sh install v4.0.0
```

## Install latest (master branch)
```bash
bash obico-install.sh install
```

## Install without linking
```bash
bash obico-install.sh install --no-link
```

## Install without autostart
```bash
bash obico-install.sh install --no-autostart
```

## Debug mode
```bash
bash obico-install.sh --debug install
```

## Dry‑run (no changes made)
```bash
bash obico-install.sh --dry-run install
```

## Update Obico
```bash
bash obico-install.sh update
```

Or update to a specific version:

```bash
bash obico-install.sh update v4.0.0
```

## Backup config + logs
```bash
bash obico-install.sh backup
```

## System health check
```bash
bash obico-install.sh doctor
```

---

# ❗ Known Limitations

- No Janus/WebRTC → Obico uses MJPEG + snapshot  
- Requires Paxx Extended Firmware  
- Requires internet access during installation  
- Autostart waits for Klippy to be ready (5 seconds delay)

---

# ❤️ Credits

- **Obico / Moonraker‑Obico**  
  https://github.com/TheSpaghettiDetective/moonraker-obico
- **Paxx Extended Firmware**  
  https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware
- **D3LZ Community U1 Obico Work**  
  https://github.com/D3LZ-D3LZ-D3LZ/u1obico
- **This Installer**  
  https://github.com/Tareku99/snapmaker_u1_obico

---

# 📜 Changelog
See the full version history here:  
[CHANGELOG](CHANGELOG.md)

---

# 📄 License
This project is licensed under the MIT License.  
See the full text here:  
[LICENSE](LICENSE)