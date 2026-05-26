#!/bin/bash
# obico-install.sh - Install / manage moonraker-obico on Snapmaker U1 (Extended Firmware)
# Usage:
#   bash obico-install.sh [global-flags] <command> [command-flags] [args...]
#
# Commands:
#   install        Install Obico (default if no command is given)
#   uninstall      Uninstall Obico
#   restore        Restore persistence/permissions after firmware update
#   update         Update Obico to latest or specified version
#   backup         Backup Obico config and metadata
#   doctor         Run health checks
#
# Global flags:
#   --debug        Verbose output, show commands and details
#   --dry-run      Show what would happen, but do not change the system
#
# Command flags:
#   install:
#     --no-link       Do not run the Obico linking flow
#     --no-autostart  Do not install the Moonraker autostart component
#
#   uninstall:
#     --keep-config   Keep config and logs when uninstalling
#
# Installer Version: v2.0.0

set -e

# =========================
# GLOBALS & CONSTANTS
# =========================

INSTALLER_VERSION="v2.0.0"

OBICO_DIR="/userdata/moonraker-src"
OBICO_LOGS="/userdata/obico-logs"
OBICO_VENV="/userdata/obico-venv"
OBICO_CFG="$OBICO_DIR/moonraker-obico.cfg"

MOONRAKER_COMPONENT="/home/lava/moonraker/moonraker/components/obico_starter.py"
MOONRAKER_EXTRA_CFG="/home/lava/printer_data/config/extended/moonraker/05_obico.cfg"
MOONRAKER_VERSION_CFG="/home/lava/printer_data/config/extended/moonraker/05_obico_version.cfg"

BACKUP_DIR="/userdata/obico-backup"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEBUG=0
DRY_RUN=0

INSTALL_NO_LINK=0
INSTALL_NO_AUTOSTART=0
UNINSTALL_KEEP_CONFIG=0

COMMAND=""
COMMAND_ARG=""   # e.g. version for install/update

log()     { echo -e "${GREEN}[obico]${NC} $1"; }
warn()    { echo -e "${YELLOW}[obico]${NC} $1"; }
error()   { echo -e "${RED}[obico]${NC} $1"; exit 1; }
info()    { echo -e "${BLUE}[obico]${NC} $1"; }

run_cmd() {
    # Wrapper that respects --dry-run and --debug
    if [ "$DEBUG" -eq 1 ]; then
        echo -e "${BLUE}[debug]${NC} $*"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi
    "$@"
}

# =========================
# CLEANUP HANDLER
# =========================

cleanup_partial_install() {
    warn "Cleaning up partial installation..."
    rm -rf "$OBICO_DIR.tmp" "$OBICO_VENV.tmp" /tmp/moonraker-obico.tar.gz 2>/dev/null || true
    rm -f "$MOONRAKER_COMPONENT" "$MOONRAKER_EXTRA_CFG" 2>/dev/null || true
}

trap cleanup_partial_install ERR

# =========================
# FLAG & COMMAND PARSING
# =========================

print_usage() {
    cat << EOF
Usage:
  bash obico-install.sh [global-flags] <command> [command-flags] [args...]

Commands:
  install        Install Obico (default if omitted)
  uninstall      Uninstall Obico
  restore        Restore persistence/permissions after firmware update
  update         Update Obico to latest or specified version
  backup         Backup Obico config and metadata
  doctor         Run health checks

Global flags:
  --debug        Verbose output, show commands and details
  --dry-run      Show what would happen, but do not change the system

Install flags:
  --no-link       Do not run the Obico linking flow
  --no-autostart  Do not install the Moonraker autostart component

Uninstall flags:
  --keep-config   Keep config and logs when uninstalling

Examples:
  bash obico-install.sh install
  bash obico-install.sh --debug install --no-link
  bash obico-install.sh install v4.0.0
  bash obico-install.sh update
  bash obico-install.sh update v4.0.0
  bash obico-install.sh uninstall --keep-config
  bash obico-install.sh --dry-run doctor
EOF
}

parse_args() {
    local args=("$@")
    local i=0

    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"

        case "$arg" in
            --debug)
                DEBUG=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            install|uninstall|restore|update|backup|doctor)
                if [ -n "$COMMAND" ]; then
                    error "Multiple commands specified: '$COMMAND' and '$arg'"
                fi
                COMMAND="$arg"
                ;;
            --no-link)
                INSTALL_NO_LINK=1
                ;;
            --no-autostart)
                INSTALL_NO_AUTOSTART=1
                ;;
            --keep-config)
                UNINSTALL_KEEP_CONFIG=1
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                # First non-flag, non-command after command is treated as COMMAND_ARG
                if [ -z "$COMMAND" ]; then
                    # No command yet: treat as command if matches, else error
                    error "Unknown argument before command: $arg"
                else
                    if [ -z "$COMMAND_ARG" ]; then
                        COMMAND_ARG="$arg"
                    else
                        error "Unexpected extra argument: $arg"
                    fi
                fi
                ;;
        esac
        i=$((i + 1))
    done

    # Default command if none specified
    if [ -z "$COMMAND" ]; then
        COMMAND="install"
    fi
}

# =========================
# CORE VALIDATION FUNCTIONS
# =========================

check_root() {
    [ "$(id -u)" = "0" ] || error "Please run as root: bash obico-install.sh"
}

check_internet() {
    log "Checking internet connectivity..."
    if ! run_cmd curl -s --max-time 5 https://api.github.com > /dev/null 2>&1; then
        error "No internet access or GitHub API unreachable."
    fi
    log "Internet OK."
}

check_extended_firmware() {
    [ -f /home/lava/printer_data/config/extended/extended2.cfg ] || \
        error "Extended firmware not detected."
    log "Extended firmware detected."
}

check_python() {
    command -v python3 >/dev/null 2>&1 || error "python3 not found."
    python3 - <<EOF || error "Python venv module missing."
import venv
EOF
    log "Python and venv module OK."
}

check_moonraker_paths() {
    [ -d /home/lava/moonraker/moonraker/components ] || \
        error "Moonraker components directory missing."

    [ -d /home/lava/printer_data/config/extended/moonraker ] || \
        error "Moonraker extended config directory missing."

    log "Moonraker paths OK."
}

check_existing_install() {
    if [ -d "$OBICO_DIR" ] || [ -d "$OBICO_VENV" ]; then
        warn "Existing Obico installation detected."
        return 0
    fi
    return 1
}

# =========================
# VERSION FETCHING
# =========================

fetch_latest_tag() {
    if [ -n "$1" ]; then
        OBICO_TAG="$1"
        log "Using user-specified version: $OBICO_TAG"
        return
    fi

    log "Fetching latest Obico release tag..."

    OBICO_TAG=$(curl -s https://api.github.com/repos/TheSpaghettiDetective/moonraker-obico/releases/latest \
        | grep '"tag_name"' \
        | head -n1 \
        | sed 's/.*"tag_name": "//; s/".*//')

    [ -z "$OBICO_TAG" ] && error "Failed to fetch latest release tag."

    log "Latest release detected: $OBICO_TAG"
}

# =========================
# DOWNLOAD + INTEGRITY CHECK
# =========================

download_obico() {
    log "Downloading moonraker-obico $OBICO_TAG..."

    run_cmd rm -rf "$OBICO_DIR.tmp"
    run_cmd mkdir -p "$OBICO_DIR.tmp"

    local URL="https://github.com/TheSpaghettiDetective/moonraker-obico/archive/refs/tags/$OBICO_TAG.tar.gz"

    run_cmd curl -fSL "$URL" -o /tmp/moonraker-obico.tar.gz || \
        error "Failed to download Obico release."

    # Validate tarball integrity
    if ! tar -tzf /tmp/moonraker-obico.tar.gz >/dev/null 2>&1; then
        error "Downloaded tarball is corrupted."
    fi

    run_cmd tar --strip-components=1 -xzf /tmp/moonraker-obico.tar.gz -C "$OBICO_DIR.tmp"
    run_cmd rm -f /tmp/moonraker-obico.tar.gz

    run_cmd mv "$OBICO_DIR.tmp" "$OBICO_DIR"
    log "Obico source extracted."
}

# =========================
# VENV HEALTH CHECK
# =========================

check_venv_health() {
    if [ ! -d "$OBICO_VENV" ]; then
        return 0
    fi

    warn "Existing Obico venv detected. Checking health..."

    if [ ! -f "$OBICO_VENV/bin/python" ] || \
       [ ! -f "$OBICO_VENV/bin/pip" ] || \
       [ ! -d "$OBICO_VENV/lib" ]; then

        warn "The existing venv appears corrupted."

        if [ "$DRY_RUN" -eq 1 ]; then
            warn "Dry-run: would recreate venv."
            return 0
        fi

        read -p "Recreate the venv? (yes/no): " ANSWER
        if [ "$ANSWER" != "yes" ]; then
            error "Aborting installation due to corrupted venv."
        fi

        run_cmd rm -rf "$OBICO_VENV"
    fi
}

# =========================
# CREATE VENV
# =========================

create_venv() {
    log "Creating Python virtual environment..."

    run_cmd rm -rf "$OBICO_VENV.tmp"
    run_cmd python3 -m venv "$OBICO_VENV.tmp"

    if [ "$DRY_RUN" -eq 0 ]; then
        source "$OBICO_VENV.tmp/bin/activate"
        pip install --upgrade pip
        pip install -r "$OBICO_DIR/requirements.txt"
        deactivate
    fi

    run_cmd mv "$OBICO_VENV.tmp" "$OBICO_VENV"
    log "Venv created at $OBICO_VENV"
}

# =========================
# LOG ROTATION
# =========================

rotate_logs() {
    run_cmd mkdir -p "$OBICO_LOGS"

    local LOGFILE="$OBICO_LOGS/moonraker-obico.log"

    if [ -f "$LOGFILE" ]; then
        local SIZE
        SIZE=$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 5000000 ]; then
            warn "Rotating Obico log (size > 5MB)..."
            run_cmd mv "$LOGFILE" "$LOGFILE.1"
        fi
    fi
}

# =========================
# CREATE CONFIG
# =========================

create_config() {
    log "Creating config file..."
    run_cmd mkdir -p "$OBICO_LOGS"

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would prompt for Obico URL and write config."
        return
    fi

    echo
    echo "Choose your Obico server type:"
    echo "  1) Obico Cloud (default)"
    echo "  2) Self-Hosted Obico"

    # Force explicit choice, no auto-skip
    while true; do
        read -p "Enter 1 or 2: " SERVER_CHOICE

        case "$SERVER_CHOICE" in
            1|"")
                OBICO_URL="https://app.obico.io"
                break
                ;;
            2)
                while true; do
                    read -p "Enter your Self-Hosted Obico server URL: " OBICO_URL
                    echo "$OBICO_URL" | grep -Eq '^https?://' && break
                    echo "Invalid URL format. Must start with http:// or https://"
                done
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done

    cat > "$OBICO_CFG" << EOF
[server]
url = $OBICO_URL

[moonraker]
host = 127.0.0.1
port = 7125

[webcam]
snapshot_url = http://127.0.0.1/snapshot.jpg
stream_url = http://127.0.0.1/stream.mjpg
disable_video_streaming = False

[logging]
path = $OBICO_LOGS/moonraker-obico.log
level = INFO

[tunnel]
EOF
}

# =========================
# LINK PRINTER (RESPECTS --no-link)
# =========================

link_printer() {
    if [ "$INSTALL_NO_LINK" -eq 1 ]; then
        warn "--no-link specified: skipping printer linking."
        return
    fi

    log "Linking printer to Obico..."

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would run linking flow."
        return
    fi

    cd "$OBICO_DIR"
    "$OBICO_VENV/bin/python" -m moonraker_obico.link -c "$OBICO_CFG"
}

# =========================
# VERSION LOGGING
# =========================

write_version_file() {
    log "Writing version info..."

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would write version file."
        return
    fi

    cat > "$MOONRAKER_VERSION_CFG" << EOF
[obico]
version = $OBICO_TAG
installer = $INSTALLER_VERSION
EOF
}

# =========================
# BACKUP (BASE IMPLEMENTATION)
# =========================

backup_obico() {
    log "Backing up Obico configuration..."

    run_cmd mkdir -p "$BACKUP_DIR"

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would copy config, logs, version file."
        return
    fi

    [ -f "$OBICO_CFG" ] && cp "$OBICO_CFG" "$BACKUP_DIR/"
    [ -f "$MOONRAKER_VERSION_CFG" ] && cp "$MOONRAKER_VERSION_CFG" "$BACKUP_DIR/"
    [ -d "$OBICO_LOGS" ] && cp -r "$OBICO_LOGS" "$BACKUP_DIR/"

    log "Backup complete: $BACKUP_DIR"
}

# =========================
# AUTOSTART (RESPECTS --no-autostart)
# =========================

check_autostart_conflict() {
    if grep -R "server:klippy_ready" /home/lava/moonraker/moonraker/components/*.py 2>/dev/null | grep -v "obico_starter.py" >/dev/null; then
        warn "Another Moonraker component also hooks server:klippy_ready."
        warn "This may delay or interfere with Obico startup."
    fi
}

setup_autostart() {
    if [ "$INSTALL_NO_AUTOSTART" -eq 1 ]; then
        warn "--no-autostart specified: skipping autostart component."
        return
    fi

    log "Setting up Moonraker autostart component..."

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would write autostart component + config."
        return
    fi

    cat > "$MOONRAKER_COMPONENT" << EOF
import subprocess
import asyncio
import os

def load_component(config):
    return ObicoStarter(config)

class ObicoStarter:
    def __init__(self, config):
        self.server = config.get_server()
        self.server.register_event_handler(
            "server:klippy_ready", self._on_klippy_ready)

    async def _on_klippy_ready(self):
        await asyncio.sleep(5)
        env = os.environ.copy()
        env["PATH"] = "$OBICO_VENV/bin:" + env["PATH"]
        subprocess.Popen(
            ["$OBICO_VENV/bin/python", "-m", "moonraker_obico.app",
             "-c", "$OBICO_CFG",
             "-l", "$OBICO_LOGS/moonraker-obico.log"],
            cwd="$OBICO_DIR",
            env=env
        )
EOF

    echo "[obico_starter]" > "$MOONRAKER_EXTRA_CFG"
}

# =========================
# PERMISSIONS
# =========================

fix_permissions() {
    run_cmd chown -R lava:lava "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV" 2>/dev/null || true
}

# =========================
# MOONRAKER RESTART + VERIFY
# =========================

restart_moonraker() {
    log "Restarting Moonraker..."
    run_cmd /etc/init.d/S61moonraker restart
}

verify_moonraker_restart() {
    log "Waiting for Moonraker to come back online..."

    for i in {1..20}; do
        if curl -s http://127.0.0.1:7125/server/info >/dev/null 2>&1; then
            log "Moonraker is online."
            return
        fi
        sleep 1
    done

    error "Moonraker failed to restart."
}

# =========================
# VERIFY OBICO PROCESS
# =========================

verify_obico() {
    if pgrep -f moonraker_obico.app > /dev/null; then
        log "✓ Obico is running."
    else
        warn "Obico is not running yet. Check logs:"
        warn "  tail -f $OBICO_LOGS/moonraker-obico.log"
    fi
}

# =========================
# DOCTOR (SYSTEM HEALTH CHECK)
# =========================

doctor_obico() {
    log "Running Obico system health checks..."

    echo
    info "1. Checking Moonraker..."
    if curl -s http://127.0.0.1:7125/server/info >/dev/null 2>&1; then
        log "Moonraker reachable."
    else
        warn "Moonraker NOT reachable."
    fi

    echo
    info "2. Checking Obico process..."
    if pgrep -f moonraker_obico.app >/dev/null; then
        log "Obico process running."
    else
        warn "Obico process NOT running."
    fi

    echo
    info "3. Checking venv..."
    if [ -f "$OBICO_VENV/bin/python" ]; then
        log "Venv OK."
    else
        warn "Venv missing or corrupted."
    fi

    echo
    info "4. Checking config..."
    if [ -f "$OBICO_CFG" ]; then
        log "Config OK."
    else
        warn "Config missing."
    fi

    echo
    info "5. Checking disk space..."
    df -h /userdata

    echo
    info "6. Checking webcam snapshot..."
    if curl -s --max-time 3 http://127.0.0.1/snapshot.jpg >/dev/null; then
        log "Webcam snapshot reachable."
    else
        warn "Webcam snapshot NOT reachable."
    fi

    echo
    log "Doctor check complete."
}

# =========================
# UNINSTALL (RESPECTS --keep-config)
# =========================

uninstall_obico() {
    warn "You are about to uninstall Obico from this printer."

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would uninstall Obico."
        return
    fi

    read -p "Are you sure? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        error "Uninstall cancelled."
    fi

    warn "Stopping Obico..."
    run_cmd pkill -f moonraker_obico.app || true

    warn "Removing files..."

    if [ "$UNINSTALL_KEEP_CONFIG" -eq 1 ]; then
        warn "--keep-config: preserving config + logs."
        run_cmd rm -rf "$OBICO_DIR" "$OBICO_VENV"
    else
        run_cmd rm -rf "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV"
    fi

    run_cmd rm -f "$MOONRAKER_COMPONENT" "$MOONRAKER_EXTRA_CFG" "$MOONRAKER_VERSION_CFG"

    log "Restarting Moonraker..."
    run_cmd /etc/init.d/S61moonraker restart

    log "Obico uninstalled."
}

# =========================
# RESTORE AFTER FIRMWARE UPDATE
# =========================

restore_obico() {
    log "Restoring Obico after firmware update..."

    run_cmd touch /oem/.debug
    fix_permissions
    run_cmd /etc/init.d/S61moonraker restart

    log "Restore complete."
}

# =========================
# UPDATE OBICO
# =========================

update_obico() {
    log "Updating Obico..."

    check_root
    check_internet
    check_extended_firmware
    check_python
    check_moonraker_paths

    fetch_latest_tag "$COMMAND_ARG"

    warn "Stopping Obico..."
    run_cmd pkill -f moonraker_obico.app || true

    download_obico
    check_venv_health
    create_venv
    write_version_file
    fix_permissions

    restart_moonraker
    verify_moonraker_restart
    verify_obico

    log "Update complete."
}

# =========================
# INSTALL OBICO
# =========================

install_obico() {
    check_root
    check_internet
    check_extended_firmware
    check_python
    check_moonraker_paths

    if check_existing_install; then
        warn "Existing installation detected. Continuing will overwrite files."
        if [ "$DRY_RUN" -eq 0 ]; then
            read -p "Continue? (yes/no): " ANSWER
            [ "$ANSWER" = "yes" ] || error "Installation cancelled."
        fi
    fi

    # Enable persistence
    run_cmd touch /oem/.debug

    fetch_latest_tag "$COMMAND_ARG"
    download_obico
    check_venv_health
    create_venv
    rotate_logs
    create_config
    link_printer
    write_version_file
    check_autostart_conflict
    setup_autostart
    fix_permissions

    restart_moonraker
    verify_moonraker_restart
    verify_obico
}

# =========================
# MAIN COMMAND ROUTER
# =========================

main() {
    parse_args "$@"

    case "$COMMAND" in
        install)
            install_obico
            ;;
        uninstall)
            uninstall_obico
            ;;
        restore)
            restore_obico
            ;;
        update)
            update_obico
            ;;
        backup)
            backup_obico
            ;;
        doctor)
            doctor_obico
            ;;
        *)
            error "Unknown command: $COMMAND"
            ;;
    esac
}

main "$@"
