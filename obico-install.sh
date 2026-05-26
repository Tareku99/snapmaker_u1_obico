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
COMMAND_ARG=""

log()     { echo -e "${GREEN}[obico]${NC} $1"; }
warn()    { echo -e "${YELLOW}[obico]${NC} $1"; }
error()   { echo -e "${RED}[obico]${NC} $1"; exit 1; }
info()    { echo -e "${BLUE}[obico]${NC} $1"; }

run_cmd() {
    if [ "$DEBUG" -eq 1 ]; then
        echo -e "${BLUE}[debug]${NC} $*"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        return 0
    fi
    "$@"
}

confirm_yes() {
    local ANSWER
    read -t 0.01 -n 10000 discard 2>/dev/null || true

    while true; do
        printf "%s [y/N]: " "$1"
        read ANSWER
        case "${ANSWER,,}" in
            y|yes) return 0 ;;
            n|no|"") return 1 ;;
            *) echo "Please enter yes or no." ;;
        esac
    done
}

# =========================
# GENERALIZED SPINNER
# =========================
# Usage:
#   long_command &
#   show_spinner $! "Doing something"
#
show_spinner() {
    local pid=$1
    local label="$2"
    local delay=0.1
    local spin='-\|/'

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r[%c] %s..." "${spin:0:1}" "$label"
        spin="${spin:1}${spin:0:1}"
        sleep $delay
    done
    printf "\r[✓] %s complete.      \n" "$label"
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
  --debug        Verbose output
  --dry-run      Do not modify system

Install flags:
  --no-link       Skip linking flow
  --no-autostart  Skip autostart component

Uninstall flags:
  --keep-config   Preserve config + logs
EOF
}

parse_args() {
    local args=("$@")
    local i=0

    while [ $i -lt ${#args[@]} ]; do
        local arg="${args[$i]}"

        case "$arg" in
            --debug) DEBUG=1 ;;
            --dry-run) DRY_RUN=1 ;;
            install|uninstall|restore|update|backup|doctor)
                if [ -n "$COMMAND" ]; then
                    error "Multiple commands specified: '$COMMAND' and '$arg'"
                fi
                COMMAND="$arg"
                ;;
            --no-link) INSTALL_NO_LINK=1 ;;
            --no-autostart) INSTALL_NO_AUTOSTART=1 ;;
            --keep-config) UNINSTALL_KEEP_CONFIG=1 ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                if [ -z "$COMMAND" ]; then
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

    if [ -z "$COMMAND" ]; then
        COMMAND="install"
    fi
}

# =========================
# CORE VALIDATION
# =========================

check_root() {
    [ "$(id -u)" = "0" ] || error "Please run as root."
}

check_internet() {
    log "Checking internet..."

    (
        curl -s --max-time 5 https://api.github.com >/dev/null
    ) &
    show_spinner $! "Checking internet connectivity"

    if ! curl -s --max-time 5 https://api.github.com >/dev/null; then
        error "No internet or GitHub unreachable."
    fi

    log "Internet OK."
}

check_extended_firmware() {
    [ -f /home/lava/printer_data/config/extended/extended2.cfg ] || \
        error "Extended firmware not detected."
    log "Extended firmware detected."
}

check_python() {
    command -v python3 >/dev/null 2>&1 || error "python3 missing."

    (
        python3 - <<EOF
import venv
EOF
    ) &
    show_spinner $! "Checking Python environment"

    log "Python OK."
}

check_moonraker_paths() {
    [ -d /home/lava/moonraker/moonraker/components ] || \
        error "Moonraker components missing."
    [ -d /home/lava/printer_data/config/extended/moonraker ] || \
        error "Moonraker extended config missing."
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
    # If user passed a version manually, use it
    if [ -n "$1" ]; then
        OBICO_TAG="$1"
        return
    fi

    # Default: use master branch
    OBICO_TAG="master"
}

# =========================
# DOWNLOAD + EXTRACT
# =========================

download_obico() {
    log "Downloading moonraker-obico $OBICO_TAG..."

    (
        rm -rf "$OBICO_DIR.tmp"
        mkdir -p "$OBICO_DIR.tmp"

        if [ "$OBICO_TAG" = "master" ]; then
            URL="https://github.com/TheSpaghettiDetective/moonraker-obico/archive/refs/heads/master.tar.gz"
        else
            URL="https://github.com/TheSpaghettiDetective/moonraker-obico/archive/refs/tags/$OBICO_TAG.tar.gz"
        fi

        curl -fSL "$URL" -o /tmp/moonraker-obico.tar.gz || exit 1
        tar --strip-components=1 -xzf /tmp/moonraker-obico.tar.gz -C "$OBICO_DIR.tmp"
        rm -f /tmp/moonraker-obico.tar.gz
        mv "$OBICO_DIR.tmp" "$OBICO_DIR"
    ) &
    show_spinner $! "Downloading and extracting Obico"
    wait

    log "Obico source extracted."
}

# =========================
# VENV HEALTH
# =========================

check_venv_health() {
    if [ ! -d "$OBICO_VENV" ]; then
        return 0
    fi

    warn "Existing venv detected. Checking..."

    if [ ! -f "$OBICO_VENV/bin/python" ] || \
       [ ! -f "$OBICO_VENV/bin/pip" ] || \
       [ ! -d "$OBICO_VENV/lib" ]; then

        warn "Venv appears corrupted."

        if [ "$DRY_RUN" -eq 1 ]; then
            warn "Dry-run: would recreate venv."
            return 0
        fi

        if ! confirm_yes "Recreate venv?"; then
            error "Aborting due to corrupted venv."
        fi

        rm -rf "$OBICO_VENV"
    fi
}

# =========================
# CREATE VENV
# =========================

create_venv() {
    log "Creating Python virtual environment..."

    (
        rm -rf "$OBICO_VENV.tmp"
        python3 -m venv "$OBICO_VENV.tmp"
        source "$OBICO_VENV.tmp/bin/activate"
        pip install --upgrade pip >/dev/null 2>&1
        pip install -r "$OBICO_DIR/requirements.txt" >/dev/null 2>&1
        deactivate
        rm -rf "$OBICO_VENV"
        mv "$OBICO_VENV.tmp" "$OBICO_VENV"
    ) &
    show_spinner $! "Creating Python virtual environment"
    wait

    log "Venv created at $OBICO_VENV"
}

# =========================
# LOG ROTATION
# =========================

rotate_logs() {
    (
        mkdir -p "$OBICO_LOGS"

        local LOGFILE="$OBICO_LOGS/moonraker-obico.log"

        if [ -f "$LOGFILE" ]; then
            local SIZE
            SIZE=$(stat -c%s "$LOGFILE" 2>/dev/null || echo 0)
            if [ "$SIZE" -gt 5000000 ]; then
                mv "$LOGFILE" "$LOGFILE.1"
            fi
        fi
    ) &
    show_spinner $! "Rotating Obico logs"
    wait
}

# =========================
# CREATE CONFIG
# =========================

create_config() {
    log "Creating config file..."
    mkdir -p "$OBICO_LOGS"

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would prompt for URL and write config."
        return
    fi

    echo
    echo "Choose your Obico server type:"
    echo "  1) Obico Cloud (app.obico.io)"
    echo "  2) Self-Hosted Obico"

    while true; do
        printf "Enter 1 or 2: "
        read SERVER_CHOICE
        SERVER_CHOICE=$(echo "$SERVER_CHOICE" | tr -d '[:space:]')

        case "$SERVER_CHOICE" in
            1)
                OBICO_URL="https://app.obico.io"
                break
                ;;
            2)
                while true; do
                    printf "Enter your Self-Hosted Obico server URL: "
                    read OBICO_URL
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

    PRINTER_IP=$(ip addr show | awk '/inet / && !/127.0.0.1/ { sub("/.*", "", $2); print $2; exit }')

    (
        cat > "$OBICO_CFG" << EOF
[server]
url = $OBICO_URL

[moonraker]
host = 127.0.0.1
port = 7125

[webcam]
snapshot_url = http://$PRINTER_IP/webcam/snapshot.jpg
stream_url = http://$PRINTER_IP/webcam/stream.mjpg
disable_video_streaming = False

[logging]
path = $OBICO_LOGS/moonraker-obico.log
level = INFO

[tunnel]
EOF
    ) &
    show_spinner $! "Writing Obico configuration"
    wait
}

# =========================
# LINK PRINTER
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

    (
        cd "$OBICO_DIR"
        "$OBICO_VENV/bin/python" -m moonraker_obico.link -c "$OBICO_CFG"
    ) &
    show_spinner $! "Linking printer to Obico"
    wait
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

    (
        cat > "$MOONRAKER_VERSION_CFG" << EOF
[obico_metadata]
version = $OBICO_TAG
installer = $INSTALLER_VERSION
EOF
    ) &
    show_spinner $! "Writing version metadata"
    wait
}

# =========================
# BACKUP
# =========================

backup_obico() {
    log "Backing up Obico configuration..."

    (
        mkdir -p "$BACKUP_DIR"

        [ -f "$OBICO_CFG" ] && cp "$OBICO_CFG" "$BACKUP_DIR/"
        [ -f "$MOONRAKER_VERSION_CFG" ] && cp "$MOONRAKER_VERSION_CFG" "$BACKUP_DIR/"
        [ -d "$OBICO_LOGS" ] && cp -r "$OBICO_LOGS" "$BACKUP_DIR/"
    ) &
    show_spinner $! "Backing up Obico configuration"
    wait

    log "Backup complete: $BACKUP_DIR"
}

# =========================
# AUTOSTART
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

    (
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
    ) &
    show_spinner $! "Installing autostart component"
    wait
}

# =========================
# PERMISSIONS
# =========================

fix_permissions() {
    (
        chown -R lava:lava "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV" 2>/dev/null || true
    ) &
    show_spinner $! "Fixing file permissions"
    wait
}

# =========================
# MOONRAKER RESTART + VERIFY
# =========================

restart_moonraker() {
    (
        /etc/init.d/S61moonraker restart
    ) &
    show_spinner $! "Restarting Moonraker"
    wait
}

verify_moonraker_restart() {
    log "Waiting for Moonraker to come back online..."

    (
        for i in {1..20}; do
            curl -s http://127.0.0.1:7125/server/info >/dev/null 2>&1 && exit 0
            sleep 1
        done
        exit 1
    ) &
    show_spinner $! "Verifying Moonraker startup"
    wait || error "Moonraker failed to restart."

    log "Moonraker is online."
}

# =========================
# VERIFY OBICO PROCESS
# =========================

verify_obico() {
    (
        sleep 2
        pgrep -f moonraker_obico.app >/dev/null
    ) &
    show_spinner $! "Checking Obico process"
    wait

    if pgrep -f moonraker_obico.app >/dev/null; then
        log "✓ Obico is running."
    else
        warn "Obico is not running yet. Check logs:"
        warn "  tail -f $OBICO_LOGS/moonraker-obico.log"
    fi
}

# =========================
# DOCTOR
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
# UNINSTALL
# =========================

uninstall_obico() {
    warn "You are about to uninstall Obico."

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Dry-run: would uninstall Obico."
        return
    fi

    confirm_yes "Are you sure?" || error "Uninstall cancelled."

    warn "Stopping Obico..."
    pkill -f moonraker_obico.app || true

    warn "Removing files..."

    (
        if [ "$UNINSTALL_KEEP_CONFIG" -eq 1 ]; then
            warn "--keep-config: preserving config + logs."
            rm -rf "$OBICO_DIR" "$OBICO_VENV"
        else
            rm -rf "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV"
        fi

        rm -f "$MOONRAKER_COMPONENT" "$MOONRAKER_EXTRA_CFG" "$MOONRAKER_VERSION_CFG"
    ) &
    show_spinner $! "Removing Obico files"
    wait

    (
        /etc/init.d/S61moonraker restart
    ) &
    show_spinner $! "Restarting Moonraker"
    wait

    log "Obico uninstalled."
}

# =========================
# RESTORE AFTER FIRMWARE UPDATE
# =========================

restore_obico() {
    log "Restoring Obico after firmware update..."

    (
        touch /oem/.debug
        chown -R lava:lava "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV" 2>/dev/null || true
        /etc/init.d/S61moonraker restart
    ) &
    show_spinner $! "Restoring Obico installation"
    wait

    log "Restore complete."
}

# =========================
# PRE-INSTALL CLEANUP
# =========================

pre_install_cleanup() {
    warn "Running pre-install cleanup..."

    (
        # Remove leftover temp dirs
        rm -rf "$OBICO_DIR.tmp" "$OBICO_VENV.tmp" /tmp/moonraker-obico.tar.gz 2>/dev/null || true

        # Remove old Obico source + venv
        rm -rf "$OBICO_DIR" "$OBICO_VENV" 2>/dev/null || true

        # Remove old Moonraker autostart components
        rm -f "$MOONRAKER_COMPONENT" "$MOONRAKER_EXTRA_CFG" "$MOONRAKER_VERSION_CFG" 2>/dev/null || true

        # Remove pip cache
        rm -rf /root/.cache/pip 2>/dev/null || true

        # Ensure logs directory exists
        mkdir -p "$OBICO_LOGS"

        # Prune old logs (>5MB or >1 backup)
        if [ -f "$OBICO_LOGS/moonraker-obico.log.1" ]; then
            rm -f "$OBICO_LOGS/moonraker-obico.log.2" 2>/dev/null || true
        fi
    ) &
    show_spinner $! "Cleaning up old Obico files"
    wait
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
    pre_install_cleanup

    fetch_latest_tag "$COMMAND_ARG"

    warn "Stopping Obico..."
    pkill -f moonraker_obico.app || true

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
    pre_install_cleanup

    if check_existing_install; then
        warn "Existing installation detected. Continuing will overwrite files."
        if [ "$DRY_RUN" -eq 0 ]; then
            confirm_yes "Continue?" || error "Installation cancelled."
        fi
    fi

    touch /oem/.debug

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
# MAIN ROUTER
# =========================

main() {
    parse_args "$@"

    case "$COMMAND" in
        install)   install_obico ;;
        uninstall) uninstall_obico ;;
        restore)   restore_obico ;;
        update)    update_obico ;;
        backup)    backup_obico ;;
        doctor)    doctor_obico ;;
        *) error "Unknown command: $COMMAND" ;;
    esac
}

main "$@"