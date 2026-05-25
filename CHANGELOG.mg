# Changelog

## v2.0.0 — Modular Installer + Hybrid CLI Release
### Added
- Fully modular installer architecture (functions for install/update/backup/doctor/etc.)
- Hybrid CLI with subcommands (`install`, `update`, `backup`, `doctor`, `restore`, `uninstall`)
- GNU‑style flexible flag parsing (flags before or after commands)
- New global flags:
  - `--debug` (verbose output)
  - `--dry-run` (simulate actions without changes)
- New install flags:
  - `--no-link` (skip printer linking)
  - `--no-autostart` (skip Moonraker autostart component)
- New uninstall flag:
  - `--keep-config` (preserve config + logs)
- Added `update` command (upgrade Obico safely)
- Added `backup` command (config + logs)
- Added `doctor` command (system health checks)
- Added explicit Cloud vs Self‑Hosted Obico prompt
- Added versioned installer metadata (`v2.0.0`)
- Added backup directory `/userdata/obico-backup`
- Added venv health checks + corruption detection
- Added improved autostart conflict detection
- Added Moonraker restart verification + Obico process verification

### Improved
- Cleaner directory structure under `/userdata`
- More robust error handling and user guidance
- Safer installation flow with partial‑install cleanup
- Better webcam configuration defaults
- More stable autostart component behavior
- More maintainable codebase with modular functions
- Documentation updated for v2 installer, Cloud/Self‑Hosted support, and new commands

### Notes
This release introduces a complete architectural overhaul of the installer, making it more reliable, maintainable, and feature‑rich.  
It fully supports both **Obico Cloud** and **Self‑Hosted Obico** servers.

---

## v1.0.0 — Initial Production Release
### Added
- Complete rewrite of `obico-install.sh`
- Added Python + venv validation
- Added Moonraker path validation
- Added partial-install cleanup handler
- Added tarball integrity verification
- Added log rotation (5MB threshold)
- Added version logging to Moonraker config
- Added venv corruption detection (with user confirmation)
- Added autostart conflict detection
- Added Moonraker restart verification
- Added uninstall confirmation
- Added restore mode for firmware updates
- Added clean directory structure under `/userdata`

### Improved
- Installer reliability and safety
- Error messages and user guidance
- Webcam configuration defaults
- Autostart component stability
- Overall repo structure and documentation

### Notes
This is the first stable, production-ready release of the Snapmaker U1 Obico installer.  
Copy of https://github.com/D3LZ-D3LZ-D3LZ/u1obico with many improvements.
