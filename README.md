# 🚀 Obico for Snapmaker U1 (Extended Firmware)

AI‑powered print monitoring and failure detection for the **Snapmaker U1**, using **Moonraker‑Obico** and the **Paxx Extended Firmware**.

This installer automatically:
- Fetches the **latest Obico source (master branch)**
- Installs it inside a **Python virtual environment**
- Creates a **Moonraker autostart component**
- Configures webcam snapshot mode
- Links your printer to Obico (Cloud or Self‑Hosted)
- Ensures everything survives firmware updates
- Provides update, backup, and health‑check tools

---

# 📦 Requirements

- **Snapmaker U1 running Paxx Extended Firmware**  
  https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware
- **SSH access enabled**
- **Internet connection**
- **Obico account**  
  - **Obico Cloud** → https://app.obico.io  
  - **Self‑Hosted Obico** → any custom server URL  
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
- Fetch the **latest Obico source (master branch)**  
- Install into `/userdata/obico-venv`  
- Create config + logs  
- Link your printer (unless `--no-link` is used)  
- Install a Moonraker autostart component  
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

## Autostart Component

A Moonraker component is created at:

```
/home/lava/moonraker/moonraker/components/obico_starter.py
```

And enabled via:

```
/home/lava/printer_data/config/extended/moonraker/05_obico.cfg
```

This launches Obico automatically when Klippy becomes ready.

---

# 📷 Webcam Support

Paxx Extended Firmware exposes the internal camera at:

```
http://<printer-ip>/webcam/snapshot.jpg
http://<printer-ip>/webcam/stream.mjpg
```

The installer automatically detects your printer’s LAN IP and writes the correct URLs into:

```
/userdata/moonraker-src/moonraker-obico.cfg
```

Obico uses **snapshot mode** on the U1 (no Janus/WebRTC).  
This is normal and fully supported.

---

# 📝 Configuration File

Created at:

```
/userdata/moonraker-src/moonraker-obico.cfg
```

Includes:
- Obico server URL (Cloud or Self‑Hosted)
- Moonraker host/port  
- Webcam snapshot URLs  
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

# 🔄 Restore After Firmware Update

Paxx firmware updates wipe overlay persistence.  
To restore Obico:

```bash
bash obico-install.sh restore
```

This:
- Re‑enables persistence  
- Fixes permissions  
- Restarts Moonraker  

Your Obico install remains intact.

---

# 🧪 Advanced Usage

## Install a specific Obico version
```bash
bash /tmp/obico-install.sh install v4.0.0
```

## Install latest (master branch)
```bash
bash /tmp/obico-install.sh install
```

## Install without linking
```bash
bash /tmp/obico-install.sh install --no-link
```

## Install without autostart
```bash
bash /tmp/obico-install.sh install --no-autostart
```

## Debug mode
```bash
bash /tmp/obico-install.sh --debug install
```

## Dry‑run (no changes made)
```bash
bash /tmp/obico-install.sh --dry-run install
```

## Update Obico
```bash
bash /tmp/obico-install.sh update
```

Or update to a specific version:
```bash
bash /tmp/obico-install.sh update v4.0.0
```

## Backup config + logs
```bash
bash /tmp/obico-install.sh backup
```

## System health check
```bash
bash /tmp/obico-install.sh doctor
```

---

# ❗ Known Limitations

- No Janus/WebRTC → Obico uses snapshot mode only  
- Requires Paxx Extended Firmware  
- Requires internet access during installation  
- Autostart waits for Klippy to be ready (5 seconds delay)

---

# ❤️ Credits

### Obico / Moonraker‑Obico  
https://github.com/TheSpaghettiDetective/moonraker-obico

### Paxx Extended Firmware  
https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware

### D3LZ Community U1 Obico Work  
https://github.com/D3LZ-D3LZ-D3LZ/u1obico

### This Installer  
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