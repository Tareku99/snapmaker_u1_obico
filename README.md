🚀 Moonraker‑Obico for Snapmaker U1
AI Failure Detection for the Snapmaker U1 using Obico (Cloud or Self‑Hosted)

This project installs Moonraker‑Obico on the Snapmaker U1 running the Paxx Extended Firmware, enabling AI‑powered print monitoring and failure detection.

📦 Prerequisites
Snapmaker U1 with Paxx Extended Firmware  
Official repo: https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware

Internet connection

Obico account (cloud or self‑hosted)

SSH access enabled in Paxx firmware

Basic familiarity with SSH/terminal

⚡ Quick Install
SSH into your U1 and run:

bash
curl -fsSL https://raw.githubusercontent.com/D3LZ-D3LZ-D3LZ/u1obico/main/obico-install.sh -o /tmp/obico-install.sh
bash /tmp/obico-install.sh
The installer will:

Check prerequisites

Download moonraker‑obico

Install Python dependencies

Ask for your Obico server URL

Guide you through linking the printer

Set up autostart via a Moonraker component

Restart Moonraker and verify Obico is running

🧠 How the Installer Works
Persistence
The script enables overlay persistence via /oem/.debug so changes survive reboots.

Autostart
Because the U1 uses BusyBox (no systemd), Obico is launched using a Moonraker Python component that runs when Klipper is ready.
This component lives in /home/lava, which persists without overlay.

Webcam Support
The Paxx firmware exposes the internal camera at:

http://127.0.0.1/snapshot.jpg

http://127.0.0.1/stream.mjpg

Obico uses snapshot mode (~0.1 FPS) because Janus/WebRTC is not available on the U1.
This is expected and fully sufficient for AI failure detection.

✅ After Installation
Printer appears as Operational in Obico

Snapshots update roughly every 10 seconds when idle

You may see:

Webcam Streaming Failed (Janus)

This is normal — the U1 does not support Janus streaming.
Obico automatically falls back to snapshot mode.

🗑️ Uninstall
bash
bash /tmp/obico-install.sh uninstall
🔄 After Firmware Upgrades
Paxx firmware updates remove /oem/.debug, wiping overlay‑persisted changes.

Obico’s source and config survive in:

/userdata

/home/lava

…but persistence and file ownership must be restored after each firmware update.

📝 Notes
This README is tailored for the Snapmaker U1 running Paxx Extended Firmware and references the official firmware repository above.
