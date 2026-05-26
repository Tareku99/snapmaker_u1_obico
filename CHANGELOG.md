# Changelog

All notable changes to this project will be documented in this file.

## v2.0.0 — 2025‑05‑25
### Added
- Full **pre‑install cleanup system**:
  - Removes old Obico source directories
  - Removes old virtual environments
  - Removes leftover `.tmp` directories
  - Removes old Moonraker autostart components
  - Removes pip cache
  - Prunes old logs
- Automatic cleanup runs on both **install** and **update**
- Added `--no-link` and `--no-autostart` install flags
- Added `--keep-config` uninstall flag
- Added `doctor` command for system health checks
- Added `backup` command for config + metadata backup
- Added `restore` command for post‑firmware‑update recovery
- Added spinner UI for long operations
- Added version tracking file (`05_obico_version.cfg`)

### Improved
- More robust error handling with automatic rollback on failure
- Better validation of Python environment and venv health
- More reliable Moonraker restart detection
- Cleaner and safer autostart component generation
- Better log rotation handling
- Safer extraction and venv creation using `.tmp` directories

### Fixed
- Issues with partial installs leaving behind broken directories
- Problems caused by duplicate autostart components
- Old venvs causing dependency conflicts
- Tarball extraction errors not being cleaned up
- Permissions issues after firmware updates

---

## v1.0.0 — Initial Release
- Basic Obico installation for Snapmaker U1
- Manual linking flow
- Basic autostart component
- No cleanup or update logic
