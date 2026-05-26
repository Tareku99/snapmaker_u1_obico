# 📜 Changelog

All notable changes to **snapmaker_u1_obico** will be documented in this file.

---

## **v2.1.0 — 2026‑05‑25**
### 🚀 Major Update — Self‑Healing + MJPEG Release

This release introduces a fully updated installer with **self‑healing**, **MJPEG streaming**, and **automatic persistence recovery**.

#### ✨ New Features
- **MJPEG streaming enabled by default**
  - Uses `/webcam/stream.mjpg` for fast internal camera streaming
  - Snapshot fallback remains available
  - No Janus/WebRTC required

- **Self‑healing autostart component**
  - Automatically restores `/oem/.debug` if wiped by firmware updates
  - Repairs permissions on every boot
  - Ensures Obico always starts cleanly after Klippy initializes

- **Automatic restore after firmware updates**
  - No more manual `restore` command needed
  - Persistence and permissions are repaired automatically

- **Improved version metadata handling**
  - Version file stored safely at `/userdata/obico-version.cfg`
  - Prevents Moonraker config warnings

#### 🔧 Improvements
- Cleaner, safer installer logic
- Better error handling and cleanup
- More robust venv creation and validation
- Updated README to reflect new features
- Updated autostart component with permission repair logic
- Updated config generator with MJPEG stream URLs

#### 🧹 Removed / Deprecated
- Old autostart component (non‑self‑healing)
- Snapshot‑only webcam configuration
- Legacy version file path inside Moonraker config directories

---

## **v2.0.0 — 2026‑05‑20**
### Initial Public Release

- Added installation, update, uninstall, backup, and doctor commands  
- Added virtual environment installation  
- Added Moonraker autostart component  
- Added linking flow for Obico Cloud and Self‑Hosted  
- Added log rotation and cleanup  
- Added extended firmware validation  
- Added snapshot webcam support  
- Added version metadata file  

---

## **v1.0.0 — 2026‑05‑10**
### Private Internal Release

- First working prototype  
- Manual linking  
- Basic Obico startup  
- No autostart component  
- No persistence handling  
- No MJPEG support  

---

# 📝 Notes

- The installer is designed for **Paxx Extended Firmware** only.  
- `/userdata` is used for all persistent storage.  
- MJPEG streaming is the fastest camera mode supported by the U1 hardware.  

---

# ❤️ Credits

- Obico / Moonraker‑Obico  
- Paxx Extended Firmware  
- D3LZ Community U1 Obico Work  
- Snapmaker U1 community testers  

