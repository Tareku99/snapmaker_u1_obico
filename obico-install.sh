#!/bin/bash
# Install and manage Moonraker-Obico on Snapmaker U1 Extended Firmware.
set -e
set -o pipefail

INSTALLER_VERSION="v2.1.0"

USERDATA="/userdata"
OBICO_DIR="$USERDATA/moonraker-src"
OBICO_LOGS="$USERDATA/obico-logs"
OBICO_VENV="$USERDATA/obico-venv"
OBICO_CFG="$OBICO_DIR/moonraker-obico.cfg"
OBICO_VERSION_CFG="$USERDATA/obico-version.cfg"
BACKUP_DIR="$USERDATA/obico-backup"
INSTALL_LOCK="$USERDATA/.obico-installer.lock"
JANUS_DIR="$USERDATA/obico-janus"
JANUS_RUNTIME="$JANUS_DIR/runtime"
JANUS_OWNER="Snapmaker U1 Obico installer"
JANUS_RELEASE_URL="https://github.com/Tareku99/snapmaker-u1-obico-installer/releases/download/janus-u1-v1.4.3-r1/obico-janus-u1-aarch64.tar.gz"
JANUS_RELEASE_SHA256="f4972ae7cd04354cdccc96a4a9cbc7e58b3f9b66e0bcddf425487f4945542f7a"

EXTENDED_CONFIG="/home/lava/printer_data/config/extended"
MOONRAKER_COMPONENT="/home/lava/moonraker/moonraker/components/obico_starter.py"
MOONRAKER_EXTRA_CFG="$EXTENDED_CONFIG/moonraker/05_obico.cfg"
MOONRAKER_INIT="/etc/init.d/S61moonraker"
PERSISTENCE_MARKER="/oem/.debug"
MOONRAKER_INFO_URL="http://127.0.0.1:7125/server/info"
WEBCAM_SNAPSHOT_URL="http://127.0.0.1/webcam/snapshot.jpg"
U1_H264_URL="http://127.0.0.1/webcam/stream.h264"

COMMAND=""
OBICO_TAG="master"
DRY_RUN=0
DEBUG=0
INSTALL_NO_LINK=0
INSTALL_NO_AUTOSTART=0
UNINSTALL_KEEP_CONFIG=0
NATIVE_VIDEO=0
ENABLE_NATIVE_VIDEO=0
JANUS_ARCHIVE=""

STAGING_DIR=""
REPLACING_INSTALL=0
REPLACING_AUTOSTART=0
WRITING_VERSION=0
REPLACING_JANUS=0
CREATING_JANUS_DIR=0
REMOVING_PERSISTENCE_MARKER=0
MOONRAKER_RESTART_NEEDED=0
UPGRADING_AUTOSTART=0

log()   { printf '[obico] %s\n' "$*"; }
warn()  { printf '[obico] %s\n' "$*" >&2; }
error() { warn "$*"; exit 1; }

print_usage() {
    cat <<'EOF'
Usage:
  bash obico-install.sh [global-flags] [command] [command-flags] [version]

Commands:
  install [version]  Install Obico (default command)
  update [version]   Update an existing installation and preserve its config
  uninstall          Uninstall Obico
  restore            Reinstall the autostart files when their config is present
  backup             Back up Obico config, version metadata and logs
  doctor             Run health checks

Global flags:
  --debug            Show staging and download details
  --dry-run          Show planned actions without changing the system

Install flags:
  --no-link          Skip printer linking
  --no-autostart     Skip the Moonraker autostart component

Install and update flags:
  --native-video     Enable experimental native H.264 for self-hosted Obico
  --janus-bundle PATH
                     Test a local copy of the exact pinned Janus release

Uninstall flags:
  --keep-config      Save the config in the backup directory and keep logs
EOF
}

parse_args() {
    local version=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --debug) DEBUG=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --no-link) INSTALL_NO_LINK=1 ;;
            --no-autostart) INSTALL_NO_AUTOSTART=1 ;;
            --keep-config) UNINSTALL_KEEP_CONFIG=1 ;;
            --native-video) ENABLE_NATIVE_VIDEO=1 ;;
            --janus-bundle)
                shift
                [ "$#" -gt 0 ] && [ -n "$1" ] && [[ "$1" != -* ]] ||
                    error "--janus-bundle requires an archive path."
                JANUS_ARCHIVE="$1"
                ENABLE_NATIVE_VIDEO=1
                ;;
            -h|--help) print_usage; exit 0 ;;
            install|update|uninstall|restore|backup|doctor)
                [ -z "$COMMAND" ] || error "Multiple commands specified: '$COMMAND' and '$1'."
                COMMAND="$1"
                ;;
            -*) error "Unknown option: $1" ;;
            *)
                [ "$COMMAND" = install ] || [ "$COMMAND" = update ] ||
                    error "Unexpected argument: $1"
                [ -z "$version" ] || error "Unexpected extra argument: $1"
                [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] ||
                    error "Invalid Obico version: $1"
                version="$1"
                ;;
        esac
        shift
    done

    COMMAND="${COMMAND:-install}"
    OBICO_TAG="${version:-master}"
    if [ "$COMMAND" != install ] && { [ "$INSTALL_NO_LINK" -eq 1 ] || [ "$INSTALL_NO_AUTOSTART" -eq 1 ]; }; then
        error "--no-link and --no-autostart apply to install only."
    fi
    if [ "$COMMAND" != uninstall ] && [ "$UNINSTALL_KEEP_CONFIG" -eq 1 ]; then
        error "--keep-config applies to uninstall only."
    fi
    if [ "$ENABLE_NATIVE_VIDEO" -eq 1 ] && [ "$COMMAND" != install ] && [ "$COMMAND" != update ]; then
        error "--native-video and --janus-bundle apply to install or update."
    fi
}

confirm_yes() {
    local answer
    while printf '%s [y/N]: ' "$1"; do
        read -r answer || return 1
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) warn "Please enter yes or no." ;;
        esac
    done
}

show_plan() {
    case "$COMMAND" in
        install)
            log "Dry run: install Obico $OBICO_TAG, configure the server and restart Moonraker."
            if [ "$INSTALL_NO_LINK" -eq 0 ]; then log "Would run printer linking."; fi
            if [ "$INSTALL_NO_AUTOSTART" -eq 0 ]; then log "Would install Moonraker autostart."; fi
            ;;
        update)
            log "Dry run: update Obico to $OBICO_TAG, preserve config and restart Moonraker."
            ;;
        uninstall)
            log "Dry run: stop Obico, remove the installation and restart Moonraker."
            if [ "$UNINSTALL_KEEP_CONFIG" -eq 1 ]; then
                log "Would save the config to $BACKUP_DIR and leave logs in place."
            fi
            ;;
        backup) log "Dry run: back up config, version metadata and logs to $BACKUP_DIR." ;;
        restore) log "Dry run: restore persistence, permissions and configured autostart, then restart Moonraker." ;;
    esac
    if [ "$ENABLE_NATIVE_VIDEO" -eq 1 ]; then
        log "Would verify an on-printer Janus bundle and enable native H.264."
    elif [ "$COMMAND" = update ] && native_video_enabled; then
        log "Would reuse the on-printer Janus bundle and keep native H.264."
    fi
}

check_firmware() {
    [ -f "$EXTENDED_CONFIG/extended2.cfg" ] || error "Extended firmware not detected."
    [ -d "$(dirname "$MOONRAKER_COMPONENT")" ] || error "Moonraker components directory missing."
    [ -d "$(dirname "$MOONRAKER_EXTRA_CFG")" ] || error "Moonraker extended config directory missing."
    [ -x "$MOONRAKER_INIT" ] || error "Moonraker init script missing or not executable."
}

check_python() {
    command -v python3 >/dev/null 2>&1 || error "python3 missing."
    python3 -c 'import venv' || error "The firmware Python installation is missing the venv module."
}

# The lock also prevents backup or uninstall from racing an update.
lock_installer() {
    mkdir "$INSTALL_LOCK" 2>/dev/null ||
        error "Cannot acquire $INSTALL_LOCK. Check for another installer process or a stale lock."
    trap 'finish_operation "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

save_file() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        cp -pP -- "$1" "$2"
    fi
}

restore_file() {
    rm -f -- "$2" || return
    if [ -e "$1" ] || [ -L "$1" ]; then
        cp -pP -- "$1" "$2"
    fi
}

# A missing staged replacement can mean the active path was originally absent.
# The marker distinguishes that case from a failure before the old tree moved.
restore_tree() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        rm -rf -- "$2" && mv -- "$1" "$2"
    elif [ -f "$1.absent" ]; then
        rm -rf -- "$2"
    fi
}

finish_operation() {
    local status="$1" rollback_failed=0
    trap - EXIT
    trap '' INT TERM

    if [ "$status" -ne 0 ] && [ "$REPLACING_INSTALL" -eq 1 ]; then
        warn "Installation failed. Restoring the previous files."
        restore_tree "$STAGING_DIR/previous-source" "$OBICO_DIR" || rollback_failed=1
        restore_tree "$STAGING_DIR/previous-venv" "$OBICO_VENV" || rollback_failed=1
        if [ "$REPLACING_AUTOSTART" -eq 1 ]; then
            restore_file "$STAGING_DIR/previous-component" "$MOONRAKER_COMPONENT" || rollback_failed=1
            restore_file "$STAGING_DIR/previous-include" "$MOONRAKER_EXTRA_CFG" || rollback_failed=1
        fi
        if [ "$WRITING_VERSION" -eq 1 ]; then
            restore_file "$STAGING_DIR/previous-version" "$OBICO_VERSION_CFG" || rollback_failed=1
        fi
        if [ "$REPLACING_JANUS" -eq 1 ]; then
            restore_tree "$STAGING_DIR/previous-janus" "$JANUS_RUNTIME" || rollback_failed=1
        fi
        if [ "$CREATING_JANUS_DIR" -eq 1 ] && [ -d "$JANUS_DIR" ]; then
            rmdir -- "$JANUS_DIR" || rollback_failed=1
        fi
        if [ "$REMOVING_PERSISTENCE_MARKER" -eq 1 ]; then
            rm -f -- "$PERSISTENCE_MARKER" || rollback_failed=1
        fi
    fi

    if [ "$status" -ne 0 ] && [ "$MOONRAKER_RESTART_NEEDED" -eq 1 ]; then
        restart_moonraker || warn "Could not restart Moonraker after the failure."
    fi
    if [ "$rollback_failed" -eq 1 ]; then
        warn "Rollback incomplete. Previous files may be in $STAGING_DIR."
    elif [ -n "$STAGING_DIR" ]; then
        rm -rf -- "$STAGING_DIR" || warn "Could not clean up $STAGING_DIR."
    fi
    rmdir -- "$INSTALL_LOCK" || warn "Could not remove $INSTALL_LOCK."
    exit "$status"
}

download_obico() {
    local ref="refs/tags/$OBICO_TAG"
    if [ "$OBICO_TAG" = master ]; then
        ref="refs/heads/master"
    fi

    log "Downloading moonraker-obico $OBICO_TAG..."
    if [ "$DEBUG" -eq 1 ]; then
        log "GitHub archive ref: $ref"
        log "Staging files in $STAGING_DIR"
    fi
    mkdir "$STAGING_DIR/source"
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 180 \
        "https://github.com/TheSpaghettiDetective/moonraker-obico/archive/$ref.tar.gz" \
        -o "$STAGING_DIR/obico.tar.gz" || error "Could not download Obico $OBICO_TAG."
    tar --strip-components=1 -xzf "$STAGING_DIR/obico.tar.gz" -C "$STAGING_DIR/source"
    [ -f "$STAGING_DIR/source/requirements.txt" ] &&
        [ -d "$STAGING_DIR/source/moonraker_obico" ] ||
        error "The downloaded archive is missing expected Obico files."
    rm -- "$STAGING_DIR/obico.tar.gz"
}

move_aside() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        mv -- "$1" "$2"
    else
        touch "$2.absent"
    fi
}

create_venv() {
    log "Creating Python virtual environment..."
    # Create the venv at its final path so its scripts get valid shebangs.
    python3 -m venv "$OBICO_VENV" || error "Failed to create the Python virtual environment."
    "$OBICO_VENV/bin/python" -m pip install --upgrade pip
    "$OBICO_VENV/bin/python" -m pip install -r "$OBICO_DIR/requirements.txt"
}

native_video_enabled() {
    [ -f "$OBICO_VERSION_CFG" ] && grep -Fxq 'native_video = true' "$OBICO_VERSION_CFG"
}

h264_endpoint_available() {
    local camera_type
    camera_type=$(curl -fsS --max-time 2 --output /dev/null --write-out '%{content_type}' "$U1_H264_URL" 2>/dev/null || true)
    [ "$camera_type" = video/h264 ]
}

check_native_video_platform() {
    [ "$(uname -m)" = aarch64 ] && grep -Eq '^ID="?buildroot"?$' /etc/os-release ||
        error "The native-video bundle requires an ARM64 Buildroot printer."
    h264_endpoint_available || error "The native U1 H.264 camera endpoint is unavailable."
}

verify_janus_bundle() {
    local runtime="$1"
    [ -x "$runtime/bin/janus" ] &&
        [ -f "$runtime/lib/janus/plugins/libjanus_streaming.so" ] &&
        [ -f "$runtime/lib/janus/transports/libjanus_websockets.so" ] ||
        error "Janus bundle is missing the executable or required plugins."
    LD_PRELOAD= LD_AUDIT= LD_LIBRARY_PATH="$runtime/lib" "$runtime/bin/janus" --version >/dev/null ||
        error "The Janus bundle does not run on this printer."
}

janus_runtime_owned() {
    [ ! -L "$JANUS_DIR" ] && [ -d "$JANUS_RUNTIME" ] && [ ! -L "$JANUS_RUNTIME" ] &&
        [ -f "$JANUS_RUNTIME/.obico-owner" ] && [ ! -L "$JANUS_RUNTIME/.obico-owner" ] &&
        grep -Fxq "$JANUS_OWNER" "$JANUS_RUNTIME/.obico-owner"
}

janus_runtime_matches() {
    janus_runtime_owned &&
        [ ! -L "$JANUS_RUNTIME/.archive-sha256" ] &&
        [ ! -L "$JANUS_RUNTIME/.runtime-sha256" ] &&
        grep -Fxq "$JANUS_RELEASE_SHA256" "$JANUS_RUNTIME/.archive-sha256" 2>/dev/null &&
        (
            cd "$JANUS_RUNTIME" &&
                [ -s .runtime-sha256 ] &&
                [ -z "$(find bin lib -type l -print)" ] &&
                [ "$(find bin lib -type f | wc -l)" -eq "$(wc -l < .runtime-sha256)" ] &&
                sha256sum -c .runtime-sha256 >/dev/null 2>&1
        )
}

stage_janus_bundle() {
    [ ! -L "$JANUS_DIR" ] && { [ ! -e "$JANUS_DIR" ] || [ -d "$JANUS_DIR" ]; } ||
        error "An unmanaged Janus path already exists at $JANUS_DIR."
    if [ -e "$JANUS_RUNTIME" ] || [ -L "$JANUS_RUNTIME" ]; then
        janus_runtime_owned || error "An unmanaged Janus runtime already exists at $JANUS_RUNTIME."
    fi
    if [ -z "$JANUS_ARCHIVE" ] && janus_runtime_matches; then
        verify_janus_bundle "$JANUS_RUNTIME"
        return
    fi

    local actual
    if [ -z "$JANUS_ARCHIVE" ]; then
        log "Downloading the ARM64 Janus bundle..."
        curl -fsSL --retry 2 --connect-timeout 10 --max-time 180 \
            "$JANUS_RELEASE_URL" -o "$STAGING_DIR/janus.tar.gz" ||
            error "Could not download the pinned Janus release."
    else
        [ -f "$JANUS_ARCHIVE" ] || error "The local copy of the pinned Janus archive is missing."
        cp -- "$JANUS_ARCHIVE" "$STAGING_DIR/janus.tar.gz"
    fi
    actual=$(sha256sum "$STAGING_DIR/janus.tar.gz")
    [ "${actual%% *}" = "$JANUS_RELEASE_SHA256" ] ||
        error "Janus archive does not match the pinned release SHA-256."
    mkdir "$STAGING_DIR/janus"
    tar -xzf "$STAGING_DIR/janus.tar.gz" -C "$STAGING_DIR/janus"
    (
        cd "$STAGING_DIR/janus"
        [ -z "$(find bin lib -type l -print)" ] ||
            error "The Janus executable and libraries must be regular files."
        printf '%s\n' "$JANUS_OWNER" > .obico-owner
        printf '%s\n' "$JANUS_RELEASE_SHA256" > .archive-sha256
        find bin lib -type f -exec sha256sum '{}' \; > .runtime-sha256
        sha256sum -c .runtime-sha256 >/dev/null
        chmod -R go-w .
    )
    verify_janus_bundle "$STAGING_DIR/janus"
    chmod 755 "$STAGING_DIR/janus"
}

prepare_native_video() {
    log "Preparing native U1 H.264 streaming..."
    python3 - "$STAGING_DIR/source" "$U1_H264_URL" "$ENABLE_NATIVE_VIDEO" "$JANUS_RUNTIME" <<'PY'
import configparser
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

source = Path(sys.argv[1])
runtime = sys.argv[4]

def patch(name, *replacements):
    path = source / "moonraker_obico" / name
    text = path.read_text(encoding="utf-8")
    for old, new in replacements:
        if text.count(old) == 1:
            text = text.replace(old, new, 1)
        elif not new or old in text or text.count(new) != 1:
            raise SystemExit(f"This Obico version has unrecognized native-video code in {name}.")
    compile(text, str(path), "exec")
    path.write_text(text, encoding="utf-8")

server = ("JANUS_SERVER = os.getenv('JANUS_SERVER', '127.0.0.1')",
          "JANUS_SERVER = '127.0.0.1'")
kill_old = "            subprocess.run(['kill', pid_file.read()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)"
kill_owned = (
    "            try:\n"
    "                pid = int(pid_file.read())\n"
    "                if pid <= 0 or os.getpgid(pid) != os.getpgrp():\n"
    "                    return\n"
    "            except (ProcessLookupError, ValueError):\n"
    "                return\n"
    "            subprocess.run(['kill', str(pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)"
)

patch("janus_config_builder.py",
      ("PRECOMPILED_DIR, REQUESTED_PRECOMPILED_VARIANT, CHOSEN_PRECOMPILED_VARIANT = find_precompiled_dir()",
       f"PRECOMPILED_DIR, REQUESTED_PRECOMPILED_VARIANT, CHOSEN_PRECOMPILED_VARIANT = {runtime!r}, None, None"),
      ("(janus_bin_path, system_janus_lib_path) = find_system_janus_paths()",
       "(janus_bin_path, system_janus_lib_path) = (None, None)"))
patch("janus.py", server,
      ("        if os.getenv('JANUS_SERVER', '').strip() != '':\n"
       "            _logger.warning('Using an external Janus gateway. Not starting the built-in Janus gateway.')\n"
       "            self.start_janus_ws()\n"
       "            return\n",
       ""),
      ("'LD_LIBRARY_PATH': ld_lib_path + ':' + os.environ.get('LD_LIBRARY_PATH', '')",
       "'LD_LIBRARY_PATH': ld_lib_path"),
      ("return '/tmp/obico-janus-{janus_port}.pid'.format(janus_port=self.janus_port)",
       "return os.path.join(RUNTIME_JANUS_ETC_DIR, f'obico-janus-{self.janus_port}.pid')"),
      ("    " + kill_old, "    " + kill_owned.replace("\n", "\n    ")),
      ("        self.kill_janus_if_running()\n        run_in_thread(run_janus_forever)",
       "        self.kill_janus_if_running()\n"
       "        if is_port_open(JANUS_SERVER, self.janus_port):\n"
       "            raise RuntimeError(f'Obico Janus port {self.janus_port} is already in use')\n"
       "        run_in_thread(run_janus_forever)"))
patch("webcam_stream.py", server,
      ("f'-re -i {webcam.h264_http_url} -c:v copy'", "f'-i {webcam.h264_http_url} -c:v copy'"),
      ("from .janus_config_builder import build_janus_config",
       "from .janus_config_builder import RUNTIME_JANUS_ETC_DIR, build_janus_config"),
      ("return '/tmp/obico-ffmpeg-{rtp_port}.pid'.format(rtp_port=rtp_port)",
       "return os.path.join(RUNTIME_JANUS_ETC_DIR, f'obico-ffmpeg-{rtp_port}.pid')"),
      (kill_old, kill_owned))

cfg = source / "moonraker-obico.cfg"
settings = configparser.ConfigParser(interpolation=None)
settings.read(cfg, encoding="utf-8")
host = urlsplit(settings.get("server", "url", fallback="")).hostname
if not host or host in {"app.obico.io", "app.thespaghettidetective.com"}:
    raise SystemExit("Native H.264 is currently supported for self-hosted Obico.")

if sys.argv[3] == "1":
    text = cfg.read_text(encoding="utf-8")
    webcam = re.search(r"(?m)^\[webcam\][ \t]*\n([\s\S]*?)(?=^\[|\Z)", text)
    if not webcam:
        raise SystemExit("Could not find the [webcam] section to configure native H.264.")
    options = re.sub(
        r"(?im)^[ \t]*(?:stream_mode|h264_http_url)[ \t]*[=:][^\n]*(?:\n|$)",
        "",
        webcam[1],
    )
    options = f"stream_mode = h264_copy\nh264_http_url = {sys.argv[2]}\n" + options
    cfg.write_text(text[:webcam.start(1)] + options + text[webcam.end(1):], encoding="utf-8")
PY
    check_native_video_platform
    stage_janus_bundle
}

rotate_logs() {
    local logfile="$OBICO_LOGS/moonraker-obico.log" size
    if [ -f "$logfile" ]; then
        size=$(stat -c%s "$logfile") || return
        if [ "$size" -gt 5000000 ]; then
            mv -- "$logfile" "$logfile.1"
        fi
    fi
}

create_config() {
    local choice obico_url printer_ip
    printf '\nChoose your Obico server type:\n  1) Obico Cloud (app.obico.io)\n  2) Self-Hosted Obico\n'
    while true; do
        printf 'Enter 1 or 2: '
        read -r choice || error "No Obico server type supplied."
        case "$choice" in
            1) obico_url="https://app.obico.io"; break ;;
            2)
                while true; do
                    printf 'Enter your Self-Hosted Obico server URL: '
                    read -r obico_url || error "No Obico server URL supplied."
                    if [[ "$obico_url" =~ ^https?://[^[:space:]]+$ ]]; then
                        break
                    fi
                    warn "Enter an http:// or https:// URL."
                done
                break
                ;;
            *) warn "Enter 1 or 2." ;;
        esac
    done

    printer_ip=$(ip addr show | awk '/inet / && !/127.0.0.1/ && !found { sub("/.*", "", $2); print $2; found=1 }')
    [ -n "$printer_ip" ] || error "Could not find the printer's IP address."
    (umask 077; cat > "$STAGING_DIR/moonraker-obico.cfg" <<EOF
[server]
url = $obico_url

[moonraker]
host = 127.0.0.1
port = 7125

[webcam]
stream_url = http://$printer_ip/webcam/stream.mjpg
snapshot_url = http://$printer_ip/webcam/snapshot.jpg
disable_video_streaming = False

[logging]
path = $OBICO_LOGS/moonraker-obico.log
level = INFO

[tunnel]
EOF
    )
    mv -- "$STAGING_DIR/moonraker-obico.cfg" "$STAGING_DIR/source/moonraker-obico.cfg"
}

link_printer() (
    cd "$OBICO_DIR"
    "$OBICO_VENV/bin/python" -m moonraker_obico.link -c "$OBICO_CFG"
)

write_version_file() {
    printf 'version = %s\ninstaller = %s\n' "$OBICO_TAG" "$INSTALLER_VERSION" > "$STAGING_DIR/version"
    if [ "$NATIVE_VIDEO" -eq 1 ]; then
        printf 'native_video = true\n' >> "$STAGING_DIR/version"
    fi
    mv -- "$STAGING_DIR/version" "$OBICO_VERSION_CFG"
}

write_autostart_component() {
    local component
    component=$(mktemp "$MOONRAKER_COMPONENT.XXXXXX")
    cat > "$component" <<EOF
import asyncio
import os
import signal
import subprocess


def load_component(config):
    return ObicoStarter(config)


class ObicoStarter:
    def __init__(self, config):
        self.server = config.get_server()
        self.process = None
        self.closing = False
        self.lifecycle_lock = asyncio.Lock()
        self.server.register_event_handler(
            "server:klippy_ready", self._on_klippy_ready)

    async def _on_klippy_ready(self):
        await asyncio.sleep(5)
        async with self.lifecycle_lock:
            if self.closing or (self.process is not None and self.process.poll() is None):
                return
            await self._stop_obico()
            env = os.environ.copy()
            env["PATH"] = "$OBICO_VENV/bin:" + env["PATH"]
            self.process = subprocess.Popen(
                ["$OBICO_VENV/bin/python", "-m", "moonraker_obico.app",
                 "-c", "$OBICO_CFG", "-l", "$OBICO_LOGS/moonraker-obico.log"],
                cwd="$OBICO_DIR", env=env, start_new_session=True)

    async def _stop_obico(self):
        process, self.process = self.process, None
        if process is None:
            return
        # FFmpeg and Janus inherit Obico's private process group.
        try:
            os.killpg(process.pid, signal.SIGTERM)
            for _ in range(20):
                process.poll()
                os.killpg(process.pid, 0)
                await asyncio.sleep(0.1)
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        finally:
            process.poll()

    async def close(self):
        self.closing = True
        async with self.lifecycle_lock:
            await self._stop_obico()
EOF
    if ! chmod 644 "$component" || ! mv -f -- "$component" "$MOONRAKER_COMPONENT"; then
        rm -f -- "$component"
        error "Could not write the Moonraker autostart component."
    fi
}

setup_autostart() {
    log "Installing the Moonraker autostart component..."
    write_autostart_component
    printf '[obico_starter]\n' > "$MOONRAKER_EXTRA_CFG"
}

autostart_needs_upgrade() {
    [ -f "$MOONRAKER_EXTRA_CFG" ] && [ -f "$MOONRAKER_COMPONENT" ] &&
        grep -Fq "\"$OBICO_VENV/bin/python\", \"-m\", \"moonraker_obico.app\"" "$MOONRAKER_COMPONENT" &&
        { grep -Fxq '            self.process.terminate()' "$MOONRAKER_COMPONENT" ||
            grep -Fxq '        # Auto-restore persistence if firmware update wiped it' "$MOONRAKER_COMPONENT"; }
}

# The old starter terminated Obico alone. Retire its exact orphaned U1
# camera forwarders when upgrading it, including processes with no PID file.
retire_orphaned_u1_streams() {
    local pid parent cwd args
    for pid in $(pgrep -f '[f]fmpeg.*stream[.]h264' || true); do
        parent=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null || true)
        [ "$parent" = 1 ] || continue
        cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) || continue
        case "$cwd" in
            "$OBICO_DIR"|"$OBICO_DIR (deleted)"|"$STAGING_DIR/previous-source") ;;
            *) continue ;;
        esac
        args=$(tr '\000' '\n' 2>/dev/null < "/proc/$pid/cmdline") || continue
        if printf '%s\n' "$args" | grep -Fxq "$U1_H264_URL" &&
            printf '%s\n' "$args" | grep -Fxq 'rtp://127.0.0.1:17732?pkt_size=1300'; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}

fix_permissions() {
    chown -R lava:lava "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV"
}

probe_http() {
    curl -fsS --max-time 3 --output /dev/null "$1" 2>/dev/null
}

managed_obico_pids() {
    local pid arguments
    for pid in $(pgrep -f '[m]oonraker_obico[.]app' || true); do
        arguments=$(tr '\000' '\n' 2>/dev/null < "/proc/$pid/cmdline") || continue
        if printf '%s\n' "$arguments" | grep -Fxq "$OBICO_CFG" &&
            printf '%s\n' "$arguments" | grep -Fxq "$OBICO_VENV/bin/python"; then
            printf '%s\n' "$pid"
        fi
    done
}

obico_running() {
    [ -n "$(managed_obico_pids)" ]
}

stop_obico() {
    local pids pid attempt
    pids=$(managed_obico_pids)
    [ -n "$pids" ] || return 0

    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    for attempt in {1..10}; do
        if ! obico_running; then return 0; fi
        sleep 1
    done
    error "Obico did not stop."
}

restart_moonraker() {
    log "Restarting Moonraker..."
    "$MOONRAKER_INIT" restart || return
    if [ "$UPGRADING_AUTOSTART" -eq 1 ]; then
        retire_orphaned_u1_streams
    fi
}

verify_moonraker() {
    local attempt
    for attempt in {1..20}; do
        if probe_http "$MOONRAKER_INFO_URL"; then
            log "Moonraker is online."
            return
        fi
        sleep 1
    done
    error "Moonraker did not respond after restart."
}

verify_obico() {
    if [ ! -f "$MOONRAKER_EXTRA_CFG" ]; then return 0; fi

    local attempt
    for attempt in {1..15}; do
        if obico_running; then
            log "Obico is running."
            return
        fi
        sleep 1
    done
    warn "Obico is not running yet. Check $OBICO_LOGS/moonraker-obico.log."
}

prepare_backup_dir() {
    mkdir -p -m 700 -- "$BACKUP_DIR"
    chmod 700 -- "$BACKUP_DIR"
}

backup_config() {
    if [ -f "$OBICO_CFG" ]; then
        cp -p -- "$OBICO_CFG" "$BACKUP_DIR/"
    fi
}

backup_obico() {
    prepare_backup_dir
    backup_config
    if [ -f "$OBICO_VERSION_CFG" ]; then cp -p -- "$OBICO_VERSION_CFG" "$BACKUP_DIR/"; fi
    if [ -d "$OBICO_LOGS" ]; then cp -R -- "$OBICO_LOGS" "$BACKUP_DIR/"; fi
    log "Backup complete: $BACKUP_DIR"
}

install_or_update() {
    check_firmware
    check_python
    if [ "$COMMAND" = update ]; then
        [ -f "$OBICO_CFG" ] || error "Obico configuration is missing. Run install to configure a new installation."
    elif [ -e "$OBICO_DIR" ] || [ -e "$OBICO_VENV" ]; then
        confirm_yes "Replace the existing Obico installation and configuration?" ||
            error "Installation cancelled."
    fi

    STAGING_DIR=$(mktemp -d "$USERDATA/.obico-install.XXXXXX")
    download_obico
    if [ "$COMMAND" = update ]; then
        cp -p -- "$OBICO_CFG" "$STAGING_DIR/source/moonraker-obico.cfg"
    else
        create_config
        save_file "$MOONRAKER_COMPONENT" "$STAGING_DIR/previous-component"
        save_file "$MOONRAKER_EXTRA_CFG" "$STAGING_DIR/previous-include"
    fi
    save_file "$OBICO_VERSION_CFG" "$STAGING_DIR/previous-version"
    if [ "$ENABLE_NATIVE_VIDEO" -eq 1 ] || { [ "$COMMAND" = update ] && native_video_enabled; }; then
        NATIVE_VIDEO=1
        prepare_native_video
        if [ "$COMMAND" = update ] && autostart_needs_upgrade; then
            save_file "$MOONRAKER_COMPONENT" "$STAGING_DIR/previous-component"
            save_file "$MOONRAKER_EXTRA_CFG" "$STAGING_DIR/previous-include"
            UPGRADING_AUTOSTART=1
        fi
    fi

    if obico_running; then MOONRAKER_RESTART_NEEDED=1; fi
    stop_obico
    REPLACING_INSTALL=1
    move_aside "$OBICO_DIR" "$STAGING_DIR/previous-source"
    move_aside "$OBICO_VENV" "$STAGING_DIR/previous-venv"
    mv -- "$STAGING_DIR/source" "$OBICO_DIR"
    create_venv
    mkdir -p "$OBICO_LOGS"
    if [ "$NATIVE_VIDEO" -eq 1 ]; then
        if [ -d "$STAGING_DIR/janus" ]; then
            if [ ! -d "$JANUS_DIR" ]; then
                mkdir "$JANUS_DIR"
                CREATING_JANUS_DIR=1
            fi
            REPLACING_JANUS=1
            move_aside "$JANUS_RUNTIME" "$STAGING_DIR/previous-janus"
            mv -- "$STAGING_DIR/janus" "$JANUS_RUNTIME"
        fi
    fi

    if [ "$COMMAND" = install ]; then
        if [ "$INSTALL_NO_LINK" -eq 0 ]; then
            log "Linking printer to Obico..."
            link_printer
        fi
        REPLACING_AUTOSTART=1
        if [ "$INSTALL_NO_AUTOSTART" -eq 1 ]; then
            rm -f -- "$MOONRAKER_COMPONENT" "$MOONRAKER_EXTRA_CFG"
        else
            setup_autostart
        fi
        if [ ! -e "$PERSISTENCE_MARKER" ]; then
            REMOVING_PERSISTENCE_MARKER=1
            touch "$PERSISTENCE_MARKER"
        fi
    elif [ "$UPGRADING_AUTOSTART" -eq 1 ]; then
        REPLACING_AUTOSTART=1
        write_autostart_component
    fi

    fix_permissions
    WRITING_VERSION=1
    write_version_file
    rotate_logs || warn "Could not rotate the Obico log."
    MOONRAKER_RESTART_NEEDED=1
    restart_moonraker
    verify_moonraker
    REPLACING_INSTALL=0
    MOONRAKER_RESTART_NEEDED=0

    verify_obico
    log "Obico $COMMAND complete."
}

uninstall_obico() {
    [ -x "$MOONRAKER_INIT" ] || error "Moonraker init script missing or not executable."
    confirm_yes "Uninstall Obico?" || error "Uninstall cancelled."
    if [ "$UNINSTALL_KEEP_CONFIG" -eq 1 ]; then
        prepare_backup_dir
        backup_config
        log "Saved any existing Obico config to $BACKUP_DIR."
    fi

    stop_obico
    rm -f -- "$MOONRAKER_EXTRA_CFG" "$MOONRAKER_COMPONENT" "$OBICO_VERSION_CFG"
    rm -rf -- "$OBICO_DIR" "$OBICO_VENV"
    if janus_runtime_owned; then
        rm -rf -- "$JANUS_RUNTIME"
        rmdir -- "$JANUS_DIR" 2>/dev/null || true
    fi
    if [ "$UNINSTALL_KEEP_CONFIG" -eq 0 ]; then rm -rf -- "$OBICO_LOGS"; fi

    restart_moonraker
    log "Obico uninstalled."
}

restore_obico() {
    check_firmware
    [ -f "$OBICO_CFG" ] && [ -x "$OBICO_VENV/bin/python" ] ||
        error "Obico config or virtual environment missing. Run install to set up Obico."
    if native_video_enabled; then
        janus_runtime_matches || error "The pinned Janus runtime is missing or changed. Run update to install it."
        verify_janus_bundle "$JANUS_RUNTIME"
    fi
    touch "$PERSISTENCE_MARKER"
    mkdir -p "$OBICO_LOGS"
    fix_permissions
    if native_video_enabled; then
        if autostart_needs_upgrade; then
            write_autostart_component
            UPGRADING_AUTOSTART=1
        fi
    fi
    if [ -f "$MOONRAKER_EXTRA_CFG" ] && [ ! -f "$MOONRAKER_COMPONENT" ]; then
        setup_autostart
    fi
    restart_moonraker
    verify_moonraker
    verify_obico
    log "Restore complete."
}

doctor_obico() {
    if probe_http "$MOONRAKER_INFO_URL"; then log "Moonraker reachable."; else warn "Moonraker unreachable."; fi
    if obico_running; then log "Obico process running."; else warn "Obico process not running."; fi
    if [ -x "$OBICO_VENV/bin/python" ]; then log "Obico venv present."; else warn "Obico venv missing."; fi
    if [ -f "$OBICO_CFG" ]; then log "Obico config present."; else warn "Obico config missing."; fi
    if probe_http "$WEBCAM_SNAPSHOT_URL"; then log "Webcam snapshot reachable."; else warn "Webcam snapshot unreachable."; fi
    if native_video_enabled; then
        if janus_runtime_matches; then
            log "Pinned Janus bundle verified."
        else
            warn "Pinned Janus bundle missing or changed."
        fi
        if h264_endpoint_available; then
            log "Native U1 H.264 feed reachable."
        else
            warn "Native U1 H.264 feed unreachable."
        fi
    fi
    df -h "$USERDATA"
}

main() {
    parse_args "$@"
    if [ "$COMMAND" = doctor ]; then
        doctor_obico
        return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        show_plan
        return
    fi

    [ "$(id -u)" = 0 ] || error "Please run as root."
    lock_installer
    case "$COMMAND" in
        install|update) install_or_update ;;
        uninstall) uninstall_obico ;;
        backup) backup_obico ;;
        restore) restore_obico ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
