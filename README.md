# 🚀 Obico for Snapmaker U1 (Extended Firmware)

AI‑powered print monitoring and failure detection for the **Snapmaker U1**, using **Moonraker‑Obico** and the **Paxx Extended Firmware**.

This installer automatically:
- Fetches the **latest Obico release**
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

SSH into your Snapmaker U1 and run the following:

### 1. Clone this repository
```bash
cd /tmp
git clone https://github.com/Tareku99/snapmaker_u1_obico.git
```

### 2. Navigate into the repo
```bash
cd snapmaker_u1_obico
```

### 3. Make the installer executable
```bash
chmod +x obico-install.sh
```

### 4. Run the installer
```bash
bash obico-install.sh install
```

The installer will:
- Verify extended firmware  
- Enable persistence  
- Fetch the **latest Obico release tag**  
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
- Works out‑of‑the‑box with this installer

### Self‑Hosted Obico
Fully supported.  
During installation you will be prompted:

```
Enter your Obico server URL [https://app.obico.io]:
```

Enter your custom server URL, for example:

```
http://192.168.1.50:3334
https://obico.mydomain.com
```

The installer configures everything automatically.

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
/userdata/moonraker-src   (Obico source)
/userdata/obico-logs      (logs)
/userdata/obico-venv      (Python venv)
/userdata/obico-backup    (backups)
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

## Webcam Support

The Paxx firmware exposes the internal camera at:

```
http://127.0.0.1/snapshot.jpg
http://127.0.0.1/stream.mjpg
```

Obico uses **snapshot mode** (no Janus/WebRTC on U1).  
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

During installation, you will be prompted to link your printer.  
This uses:

```
moonraker_obico.link
```

If you prefer to link later (Cloud or Self‑Hosted), use:

```
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
bash obico-install.sh install v4.0.0
```

## Install latest release (default)
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

All notable changes to this project are documented in:

**CHANGELOG.md**  
See version history, new features, fixes, and installer updates.

---

# 📄 License

This project is licensed under the **MIT License**.  
See the full text in:

**LICENSE.md**