# Snapmaker U1 Obico Installer

This installer runs Moonraker-Obico on a Snapmaker U1 with Paxx Extended Firmware. You can link the printer to Obico Cloud or to your own Obico server for remote monitoring and print failure detection.

## Install and link your printer

You need [Paxx Extended Firmware](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware), root access over SSH, an internet connection from the printer to download the client and its Python dependencies, and an Obico account.

**1. Download the installer.** Open an SSH session to the printer as root. Use the same session for the commands below.

```bash
curl -fsSLo /tmp/obico-install.sh \
  https://raw.githubusercontent.com/Tareku99/snapmaker-u1-obico-installer/main/obico-install.sh
```

**2. Run it and choose your server.**

```bash
bash /tmp/obico-install.sh install
```

- Choose **Obico Cloud** to use [app.obico.io](https://app.obico.io).
- Choose **Self-Hosted Obico** if you already have a server. Enter its full address as seen by the printer, including the port if needed, such as `http://192.168.1.100:3334`. For server setup, see the [Obico Docker guide](https://www.obico.io/docs/server-guides/install/), the [Obico Unraid guide](https://www.obico.io/docs/server-guides/platform-specific/unraid_guide/), or the [community Unraid container](https://github.com/imagegenius/docker-obico).

**3. Follow the linking prompts.** The installer restarts Moonraker, which launches Obico shortly after Klippy is ready. Check that the printer appears online in Obico.

If you want to link later, add `--no-link` to the install command. When you are ready to link, run:

```bash
cd /userdata/moonraker-src
/userdata/obico-venv/bin/python -m moonraker_obico.link -c moonraker-obico.cfg
```

After linking, run `bash /tmp/obico-install.sh restore` to restart Moonraker and reload the config. If you manage the Obico process yourself, use `install --no-autostart` and restart that process after linking.

## Update an existing installation

Download a fresh copy of the installer with the command above, then run:

```bash
bash /tmp/obico-install.sh update
```

`update` keeps your server settings, printer link, and existing autostart settings. The installer downloads the replacement before stopping Obico. It attempts to restore the previous installation if dependency installation or the Moonraker restart check fails. If Moonraker comes up but Obico has yet to start, the installer prints a warning and keeps the update. Check the logs and the printer's status in Obico.

Use `install` when setting up Obico for the first time or when you intend to replace the configuration and link again. Both commands download from upstream `master` by default. To select a release, add its tag after the command, for example `bash /tmp/obico-install.sh update v2.2.8`. [Upstream Obico releases](https://github.com/TheSpaghettiDetective/moonraker-obico/releases)

## Native live video preview

Native video sends the U1's H.264 camera feed through Janus on the printer. It
requires an ARM64 U1 running Paxx Extended Firmware with the
`/webcam/stream.h264` endpoint and a self-hosted Obico server. Run the installer
from `/tmp` with the printer idle because it restarts Moonraker.

Once the Janus release asset is published, enable native video with
`update --native-video` for an already-linked printer or
`install --native-video` for a fresh setup.

```bash
cd /tmp
bash /tmp/obico-install.sh update --native-video
```

The installer verifies the exact release archive against its pinned SHA-256 and
stores Janus and its private libraries under `/userdata/obico-janus/runtime`.
Later updates reuse the verified copy and keep the linked config. Native video
uses this runtime and its own PID files. Uninstall removes the managed runtime
and leaves any other Janus installation in place.

To verify a draft release, copy its runtime archive to the printer, then run:

```bash
bash /tmp/obico-install.sh update --janus-bundle /tmp/obico-janus-u1-aarch64.tar.gz
```

The local archive must match the same pinned checksum as the download. An
earlier preview installation is migrated with the update command above.

## Back up, repair, or remove Obico

| What you want to do | Command |
| --- | --- |
| Copy the config, version information, and logs to `/userdata/obico-backup` | `bash /tmp/obico-install.sh backup` |
| Check Moonraker, Obico, disk space, and the local camera snapshot endpoint | `bash /tmp/obico-install.sh doctor` |
| Repair persistence and permissions after a firmware update | `bash /tmp/obico-install.sh restore` |
| Remove Obico and its logs, then restart Moonraker | `bash /tmp/obico-install.sh uninstall` |
| Remove Obico but keep the logs and a copy of the config | `bash /tmp/obico-install.sh uninstall --keep-config` |

`uninstall --keep-config` saves the config to `/userdata/obico-backup/moonraker-obico.cfg`. The backup can contain your Obico access token.

Add `--dry-run` to preview a change without making it, `--debug` to show extra download and staging details for install or update, or `--help` to see all options.

### If Obico stops starting after a firmware update

Run `restore` if the Obico config and Python environment are still present. It repairs persistence and permissions, recreates the autostart component if its Moonraker config entry survived, and restarts Moonraker. If the config entry is gone and you used autostart, back up any remaining Obico config before reinstalling and linking again.

## Troubleshooting

- **Obico is offline.** Confirm Klippy is ready, run `doctor`, and check the log with `tail -n 50 /userdata/obico-logs/moonraker-obico.log`.
- **The camera stopped working.** The generated Obico config uses the printer's IP address at install time, with `/webcam/stream.mjpg` for MJPEG and `/webcam/snapshot.jpg` for snapshots. If the printer's IP changed, check the URLs in the Obico config. `doctor` checks the local snapshot endpoint.
- **You need help.** Include the Paxx firmware version, the command you ran, and relevant installer or log output. Remove any credentials or tokens before sharing. [Report an issue](https://github.com/Tareku99/snapmaker-u1-obico-installer/issues)

### Files on the printer

| File or directory | Purpose |
| --- | --- |
| `/userdata/moonraker-src/moonraker-obico.cfg` | Obico server, link credentials, Moonraker connection, and camera settings |
| `/userdata/obico-logs/moonraker-obico.log` | Obico client log |
| `/userdata/obico-venv/` | Python environment for Obico |
| `/userdata/obico-version.cfg` | Installed client ref and installer version |
| `/userdata/obico-backup/` | Files saved by `backup` or `uninstall --keep-config` |
| `/home/lava/printer_data/config/extended/moonraker/05_obico.cfg` | Moonraker config entry that enables Obico autostart |
| `/home/lava/moonraker/moonraker/components/obico_starter.py` | Moonraker component that starts the Obico process |

## Development

Run `bash tests/installer.sh` from the repository on Linux. GitHub Actions runs the same tests with simulated printer services and temporary files.

The [Janus release runbook](docs/janus-release.md) covers building the bundle,
testing it on a U1, and publishing the exact archive the installer verifies.

Thanks to [Obico](https://github.com/TheSpaghettiDetective/moonraker-obico), [Paxx Extended Firmware](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware), and [D3LZ](https://github.com/D3LZ-D3LZ-D3LZ/u1obico).

[Changelog](CHANGELOG.md) · [MIT License](LICENSE.md)
