#!/bin/bash
# obico-install.sh - Install moonraker-obico on Snapmaker U1 (Extended Firmware)
# Usage: bash obico-install.sh

set -e

OBICO_DIR="/userdata/moonraker-src"
OBICO_LOGS="/userdata/obico-logs"
OBICO_VENV="/userdata/obico-venv"
OBICO_CFG="$OBICO_DIR/moonraker-obico.cfg"
MOONRAKER_COMPONENT="/home/lava/moonraker/moonraker/components/obico_starter.py"
MOONRAKER_EXTRA_CFG="/home/lava/printer_data/config/extended/moonraker/05_obico.cfg"
GITHUB_URL="https://github.com/TheSpaghettiDetective/moonraker-obico/archive/refs/heads/master.tar.gz"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()     { echo -e "${GREEN}[obico]${NC} $1"; }
warn()    { echo -e "${YELLOW}[obico]${NC} $1"; }
error()   { echo -e "${RED}[obico]${NC} $1"; exit 1; }

check_root() {
    [ "$(id -u)" = "0" ] || error "Please run as root: bash obico-install.sh"
}

check_internet() {
    log "Checking internet connectivity..."
    curl -s --max-time 5 https://github.com > /dev/null 2>&1 || \
        error "No internet access. Connect the U1 to the internet and try again."
    log "Internet OK."
}

check_extended_firmware() {
    [ -f /home/lava/printer_data/config/extended/extended2.cfg ] || \
        error "Extended firmware not detected."
    log "Extended firmware detected."
}

enable_persistence() {
    log "Enabling overlay persistence..."
    touch /oem/.debug
}

download_obico() {
    log "Downloading moonraker-obico..."
    rm -rf "$OBICO_DIR"
    mkdir -p "$OBICO_DIR"
    curl -fSL "$GITHUB_URL" -o /tmp/moonraker-obico.tar.gz
    tar --strip-components=1 -xzf /tmp/moonraker-obico.tar.gz -C "$OBICO_DIR"
    rm -f /tmp/moonraker-obico.tar.gz
}

create_venv() {
    log "Creating Python virtual environment..."
    rm -rf "$OBICO_VENV"
    python3 -m venv "$OBICO_VENV"
    source "$OBICO_VENV/bin/activate"
    pip install --upgrade pip
    pip install -r "$OBICO_DIR/requirements.txt"
    deactivate
    log "Venv created at $OBICO_VENV"
}

fix_permissions() {
    chown -R lava:lava "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV"
}

create_config() {
    log "Creating config file..."
    mkdir -p "$OBICO_LOGS"

    read -p "Enter your Obico server URL [https://app.obico.io]: " OBICO_URL
    OBICO_URL="${OBICO_URL:-https://app.obico.io}"

    cat > "$OBICO_CFG" << EOF
[server]
url = $OBICO_URL

[moonraker]
host = 127.0.0.1
port = 7125

[webcam]
snapshot_url = http://127.0.0.1:8080/snapshot.jpg
stream_url = http://127.0.0.1:8080/stream.mjpg
disable_video_streaming = False

[logging]
path = $OBICO_LOGS/moonraker-obico.log
level = INFO

[tunnel]
EOF
}

link_printer() {
    log "Linking printer to Obico..."
    cd "$OBICO_DIR"
    "$OBICO_VENV/bin/python" -m moonraker_obico.link -c "$OBICO_CFG"
}

setup_autostart() {
    log "Setting up Moonraker autostart component..."

    cat > "$MOONRAKER_COMPONENT" << EOF
import subprocess
import asyncio

def load_component(config):
    return ObicoStarter(config)

class ObicoStarter:
    def __init__(self, config):
        self.server = config.get_server()
        self.server.register_event_handler(
            "server:klippy_ready", self._on_klippy_ready)

    async def _on_klippy_ready(self):
        await asyncio.sleep(5)
        subprocess.Popen(
            ["$OBICO_VENV/bin/python", "-m", "moonraker_obico.app",
             "-c", "$OBICO_CFG",
             "-l", "$OBICO_LOGS/moonraker-obico.log"],
            cwd="$OBICO_DIR"
        )
EOF

    echo "[obico_starter]" > "$MOONRAKER_EXTRA_CFG"
}

restart_moonraker() {
    log "Restarting Moonraker..."
    /etc/init.d/S61moonraker restart
    sleep 30
}

verify() {
    if pgrep -f moonraker_obico.app > /dev/null; then
        log "✓ Obico is running!"
    else
        warn "Obico is not running yet. Check logs:"
        warn "  tail -f $OBICO_LOGS/moonraker-obico.log"
    fi
}

uninstall() {
    warn "Uninstalling Obico..."
    pkill -f moonraker_obico.app || true
    rm -rf "$OBICO_DIR" "$OBICO_LOGS" "$OBICO_VENV"
    rm -f "$MOONRAKER_COMPONENT" "$MOONRAKER_EXTRA_CFG"
    /etc/init.d/S61moonraker restart
    log "Uninstalled."
}

restore() {
    log "Restoring Obico after firmware update..."
    touch /oem/.debug
    fix_permissions
    /etc/init.d/S61moonraker restart
    log "Done."
}

case "${1:-install}" in
    install)
        check_root
        check_internet
        check_extended_firmware
        enable_persistence
        download_obico
        create_venv
        create_config
        link_printer
        fix_permissions
        setup_autostart
        restart_moonraker
        verify
        ;;
    uninstall)
        check_root
        uninstall
        ;;
    restore)
        check_root
        restore
        ;;
    *)
        echo "Usage: bash obico-install.sh [install|uninstall|restore]"
        exit 1
        ;;
esac
