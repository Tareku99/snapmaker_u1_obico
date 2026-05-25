# Changelog

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
Copy of https://github.com/D3LZ-D3LZ-D3LZ/u1obico with mnay improvements