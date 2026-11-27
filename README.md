# Snapmaker U1 Obico Installer

AI‑powered print monitoring and failure detection for the **Snapmaker U1**, using **Moonraker‑Obico** and the **Paxx Extended Firmware**.

This installer automatically:

- Fetches the latest Obico source (master branch)
- Installs it inside a Python virtual environment
- Configures Moonraker to launch Obico when Klippy is ready
- Enables **MJPEG streaming** (fastest internal camera mode)
- Falls back to snapshot mode if MJPEG is unavailable
- Links your printer to Obico (Cloud or Self‑Hosted)
- Includes a `restore` command for permissions, persistence and existing autostart configuration
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
curl -fsSL "https://raw.githubusercontent.com/Tareku99/snapmaker-u1-obico-installer/main/obico-install.sh?$(date +%s)" -o /tmp/obico-install.sh
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
- Install a Moonraker autostart component
- Restart Moonraker  
- Check whether Obico starts after Moonraker restarts

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
http://<unraid-ip>:3334
https://obico.mydomain.com
```

---

# 🧩 Unraid Setup (Optional)

If you want to run **Obico Server** on your Unraid system (Cloud alternative or for Self‑Hosted setups), there are two official resources you can use:

## 📦 1. Community Docker Template (imagegenius)
A maintained monolithic Obico Server container for Unraid:

<img width="386" height="278" alt="image" src="https://github.com/user-attachments/assets/8a3efa4c-7e86-443b-be78-bef91d2f6cf2" />

**Repository:**  
https://github.com/imagegenius/docker-obico

### Installation (Unraid Apps)
1. Open the **Apps** tab in Unraid.  
2. Search for **Obico**.  
3. Select the template by **imagegenius**.  
4. Configure required environment variables:
   - `HOST_IP`
   - `REDIS_URL`
   - Any additional variables listed in the template README  
5. Deploy the container.  
6. Access the Obico web UI at:  
   ```
   http://<unraid-ip>:3334
   ```

This is the easiest way to run a full Obico Server on Unraid.

---

## 📘 2. Official Obico Unraid Guide
The Obico team provides a platform‑specific guide for Unraid:

**Official Documentation:**  
https://www.obico.io/docs/server-guides/platform-specific/unraid_guide/

This guide covers:
- Preparing your Unraid environment  
- Required dependencies  
- Docker configuration  
- Networking considerations  
- Troubleshooting  

---

## 📝 Notes for Snapmaker U1 Users
- Your Snapmaker U1 will link to your **Unraid‑hosted Obico Server** the same way it links to Obico Cloud.  
- During installation, choose **Self‑Hosted Obico** and enter your Unraid server URL, for example:  
  ```
  http://<unraid-ip>:3334
  ```
- All features supported by Moonraker‑Obico work normally with a self‑hosted server.

---

# 🐳 Normal Docker Install (Official Obico Guide)

If you want to deploy a **standard Obico Server** on Linux, macOS, or Windows using Docker + Docker Compose, use the official upstream installation guide:

**Official Docker Install Guide:**  
https://www.obico.io/docs/server-guides/install/

### Summary of the Process

1. Install **Docker** and **Docker Compose**.  
2. Clone the official Obico Server repository:
   ```bash
   git clone -b release https://github.com/TheSpaghettiDetective/obico-server.git
   ```
3. Enter the directory:
   ```bash
   cd obico-server
   ```
4. Start the server:
   ```bash
   docker compose up -d
   ```
5. Access the web UI:
   ```
   http://<server-ip>:3334
   ```

### When to Use This Method

Use this method if you want:

- A **full, official Obico Server** deployment  
- Maximum configuration control  
- A standard Docker environment (not Unraid)  
- The setup recommended by the Obico developers  

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

These directories hold the installed client and its data. The Moonraker
autostart files live outside `/userdata`.

## Moonraker Autostart Component
A Moonraker component is created at:

```
/home/lava/moonraker/moonraker/components/obico_starter.py
```

And enabled via:

```
/home/lava/printer_data/config/extended/moonraker/05_obico.cfg
```

Moonraker launches Obico after Klippy reports that it is ready. Use
`install --no-autostart` if you manage the Obico process yourself.

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

# 🔄 Restore After Firmware Updates

If Obico stops starting after a firmware update, run:

```bash
bash obico-install.sh restore
```

The command re-enables persistence, reapplies permissions, and recreates the
autostart component if the Moonraker config entry is still present. If the entry
is also missing and you relied on autostart, back up the config first. Running
`install` again sets up a new config and prompts you to link the printer.

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

This saves the current config to
`/userdata/obico-backup/moonraker-obico.cfg` and leaves
`/userdata/obico-logs` in place. The saved config may contain an Obico access token.

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

Dry-run prints the planned changes without downloading files, asking for input,
or restarting services. `doctor` runs read-only health checks.

## Update Obico
```bash
bash obico-install.sh update
```

Or update to a specific version:

```bash
bash obico-install.sh update v4.0.0
```

Updates keep the existing Obico configuration, including the printer link, and
preserve the existing Moonraker autostart files. The installer downloads the
replacement source before stopping Obico and restores the previous files if
dependency installation or Moonraker verification fails.

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
  https://github.com/Tareku99/snapmaker-u1-obico-installer

---

# 📜 Changelog
See the full version history here:  
CHANGELOG.md

---

# 📄 License
This project is licensed under the MIT License.  
See [LICENSE.md](LICENSE.md).

## Development checks

Run `bash tests/installer.sh` on Linux to run the same installer regression
checks as GitHub Actions. The tests use a temporary directory and stub printer
services. To report an installer issue, use this repository’s Issues tab and
include your Paxx firmware version and relevant installer output.
