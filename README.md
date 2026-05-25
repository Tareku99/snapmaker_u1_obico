# Obico for Snapmaker U1 (Extended Firmware)

This project provides a clean, safe installer for running **moonraker‑obico** on the
**Snapmaker U1** using **Extended Firmware**.  
It installs Obico into a **dedicated Python virtual environment** inside `/userdata`,
avoiding any modification to the system Python environment.

---

## ✨ Features

- Full Obico support (cloud or self‑hosted)
- Clean installation using a Python virtual environment
- No global pip installs
- Automatic startup via a Moonraker component
- Persistent across firmware updates
- Easy uninstall and restore modes

---

## 📦 Requirements

- Snapmaker U1  
- Extended Firmware installed  
- Internet connection  
- SSH access

---

## 🚀 Installation

Run:

```
bash obico-install.sh
```

The installer will:

1. Verify Extended Firmware  
2. Create a persistent Python virtual environment  
3. Download moonraker‑obico  
4. Install dependencies into the venv  
5. Create configuration files  
6. Link your printer to Obico  
7. Register the Moonraker autostart component  
8. Restart Moonraker

After installation, Obico will start automatically whenever Moonraker starts.

---

## 🔧 Uninstall

```
bash obico-install.sh uninstall
```

This removes:

- `/userdata/moonraker-src`
- `/userdata/obico-logs`
- `/userdata/obico-venv`
- Moonraker autostart component

---

## 🔄 Restore After Firmware Update

```
bash obico-install.sh restore
```

This restores:

- Ownership of Obico directories  
- Autostart functionality  
- Persistence flag  

---

## ⚠️ Notes

- You may see a “Webcam Streaming Failed (Janus)” warning in Obico.  
  This is normal — the U1 does not include Janus. Snapshot mode works fine.
- The installer does **not** modify system Python or install global packages.

---

## 📁 File Locations

| Purpose | Path |
|--------|------|
| Obico source | `/userdata/moonraker-src` |
| Obico logs | `/userdata/obico-logs` |
| Python venv | `/userdata/obico-venv` |
| Moonraker component | `/home/lava/moonraker/moonraker/components/obico_starter.py` |
| Moonraker config entry | `/home/lava/printer_data/config/extended/moonraker/05_obico.cfg` |

---