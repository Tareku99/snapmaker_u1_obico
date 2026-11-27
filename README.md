# Snapmaker U1 Obico Installer

Install [Moonraker-Obico](https://github.com/TheSpaghettiDetective/moonraker-obico) on your Snapmaker U1 for remote print monitoring and failure detection. The installer supports Obico Cloud and self-hosted Obico.

## Install

You need a Snapmaker U1 running [Paxx Extended Firmware](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware), root access over SSH, internet access from the printer, and an Obico account.

SSH into the printer as root and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Tareku99/snapmaker-u1-obico-installer/main/obico-install.sh \
  -o /tmp/obico-install.sh &&
  bash /tmp/obico-install.sh install
```

1. Choose **Obico Cloud** or **Self-Hosted Obico**. For self-hosted, enter the server URL the printer can reach, including the port if needed, such as `http://192.168.1.100:3334`.
2. Follow the prompts to link the printer. Moonraker starts Obico once Klippy is ready.

Use `install --no-link` to skip linking, or `install --no-autostart` if you manage the Obico process yourself.

For server setup, see the [Obico Docker guide](https://www.obico.io/docs/server-guides/install/), the [Obico Unraid guide](https://www.obico.io/docs/server-guides/platform-specific/unraid_guide/), or the [community Unraid container](https://github.com/imagegenius/docker-obico).

## Manage Obico

Run these commands over SSH on the printer using the downloaded installer.

| Command | What it does |
| --- | --- |
| `bash /tmp/obico-install.sh update` | Updates the client and keeps the linked config and existing autostart settings. |
| `bash /tmp/obico-install.sh backup` | Copies the config, version information, and logs to `/userdata/obico-backup`. |
| `bash /tmp/obico-install.sh doctor` | Checks Moonraker, the Obico process, config, disk space, and the camera snapshot URL. |
| `bash /tmp/obico-install.sh restore` | Repairs persistence and permissions. See the firmware update notes below. |
| `bash /tmp/obico-install.sh uninstall` | Removes Obico and its logs, then restarts Moonraker. Add `--keep-config` to save the config to the backup directory and keep the logs. |

Add `--dry-run` to preview an operation or `--help` to see all available flags.

By default, `install` and `update` download Obico from `master`. To choose a specific release, pass its tag after the command, for example `update v2.2.8`. [Upstream Obico releases](https://github.com/TheSpaghettiDetective/moonraker-obico/releases)

## After a firmware update

If Obico stops launching, run `restore`. It recreates the autostart component if the Moonraker config entry survived. If the entry is also missing, back up the config before reinstalling and linking again.

## Troubleshooting

- **Config** lives at `/userdata/moonraker-src/moonraker-obico.cfg` and may contain your Obico access token. Keep it private when sharing diagnostics.
- **Logs** are in `/userdata/obico-logs/moonraker-obico.log`.
- **Camera** uses `/webcam/stream.mjpg` for MJPEG and `/webcam/snapshot.jpg` for snapshots in the generated config.
- **Reporting an issue** Include your Paxx firmware version, the command you ran, and relevant installer output in a [GitHub issue](https://github.com/Tareku99/snapmaker-u1-obico-installer/issues).

## Development

Run `bash tests/installer.sh` on Linux to run the regression suite. The tests simulate printer services and use temporary files.

Thanks to [Obico](https://github.com/TheSpaghettiDetective/moonraker-obico), [Paxx Extended Firmware](https://github.com/paxx12-snapmaker-u1/SnapmakerU1-Extended-Firmware), and [D3LZ](https://github.com/D3LZ-D3LZ-D3LZ/u1obico).

[Changelog](CHANGELOG.md) · [MIT License](LICENSE.md)
