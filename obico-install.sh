#!/bin/bash
# obico-install.sh - Install moonraker-obico on Snapmaker U1 (Extended Firmware)
# Usage: bash obico-install.sh

set -e

OBICO_DIR="/userdata/moonraker-src"
OBICO_LOGS="/userdata/obico-logs"
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

# ── Checks ────────────────────────────────────────────────────────────────────

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
        error "Extended firmware not detected. Please install it first: https://snapmakeru1-extended-firmware.pages.dev"
    log "Extended firmware detected."
}

check_already_installed() {
    if [ -f "$OBICO_CFG" ] && grep -q "auth_token" "$OBICO_CFG" 2>/dev/null; then
        warn "Obico appears to already be installed and linked."
        read -p "Reinstall? (y/N): " confirm
        [ "$confirm" = "y" ] || exit 0
    fi
}

# ── Install ───────────────────────────────────────────────────────────────────

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
    log "Downloaded OK."
}

install_dependencies() {
    log "Installing Python dependencies..."
    python3 -m pip install -r "$OBICO_DIR/requirements.txt" --quiet
    log "Dependencies installed."
}

fix_permissions_scripts() {
    log "Fixing script permissions..."
    chmod +x "$OBICO_DIR/scripts/"*.sh 2>/dev/null || true
    chmod +x "$OBICO_DIR/moonraker_obico/bin/ffmpeg/run.sh" 2>/dev/null || true
    chmod +x "$OBICO_DIR/moonraker_obico/bin/utils.sh" 2>/dev/null || true
}

create_config() {
    log "Creating config file..."
    cp "$OBICO_DIR/moonraker-obico.cfg.sample" "$OBICO_CFG"
    mkdir -p "$OBICO_LOGS"

    # Prompt for Obico server URL
    echo ""
    echo "  Obico server URL:"
    echo "  - Cloud (default): https://app.obico.io"
    echo "  - Self-hosted example: http://192.168.0.48:3334"
    echo ""
    read -p "Enter your Obico server URL [https://app.obico.io]: " OBICO_URL
    OBICO_URL="${OBICO_URL:-https://app.obico.io}"

    # Write config
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
    log "Config written to $OBICO_CFG"
}

link_printer() {
    log "Linking to Obico server..."
    echo ""
    warn "You will now be prompted to link your printer to Obico."
    warn "Use the manual linking method when prompted."
    echo ""
    cd "$OBICO_DIR"
    python3 -m moonraker_obico.link -c "$OBICO_CFG" || error "Linking failed. Check your Obico server URL and try again."
    log "Printer linked successfully."
}

setup_autostart() {
    log "Setting up autostart via moonraker component..."

    # Fix ownership
    chown -R lava:lava "$OBICO_DIR"
    chown -R lava:lava "$OBICO_LOGS"

    # Create moonraker component
    cat > "$MOONRAKER_COMPONENT" << 'EOF'
import subprocess
import asyncio
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from moonraker.server import Server

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
            ["/usr/bin/python3", "-m", "moonraker_obico.app",
             "-c", "/userdata/moonraker-src/moonraker-obico.cfg",
             "-l", "/userdata/obico-logs/moonraker-obico.log"],
            cwd="/userdata/moonraker-src"
        )
EOF

    # Register component in moonraker config
    if [ ! -f "$MOONRAKER_EXTRA_CFG" ]; then
        echo "[obico_starter]" > "$MOONRAKER_EXTRA_CFG"
        log "Moonraker component registered."
    else
        grep -q "obico_starter" "$MOONRAKER_EXTRA_CFG" || \
            echo -e "\n[obico_starter]" >> "$MOONRAKER_EXTRA_CFG"
        log "Moonraker component already registered."
    fi
}

restart_moonraker() {
    log "Restarting moonraker..."
    /etc/init.d/S61moonraker restart
    log "Waiting for moonraker and obico to start..."
    sleep 35
}

verify() {
    if pgrep -f moonraker_obico.app > /dev/null; then
        log "✓ Obico is running!"
    else
        warn "Obico does not appear to be running yet. Check logs:"
        warn "  tail -f $OBICO_LOGS/moonraker-obico.log"
    fi
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

uninstall() {
    warn "Uninstalling moonraker-obico..."
    pkill -f moonraker_obico.app 2>/dev/null || true
    rm -rf "$OBICO_DIR" "$OBICO_LOGS"
    rm -f "$MOONRAKER_COMPONENT"
    rm -f "$MOONRAKER_EXTRA_CFG"
    /etc/init.d/S61moonraker restart
    log "Uninstalled."
}

# ── Post-upgrade restore ──────────────────────────────────────────────────────

restore() {
    log "Restoring obico after firmware upgrade..."
    touch /oem/.debug
    chown -R lava:lava "$OBICO_DIR"
    chown -R lava:lava "$OBICO_LOGS"
    /etc/init.d/S61moonraker restart
    log "Done. Obico should start within 30 seconds."
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-install}" in
    install)
        echo ""
        echo "  Obico Installer for Snapmaker U1"
        echo "  ================================="
        echo ""
        check_root
        check_internet
        check_extended_firmware
        check_already_installed
        enable_persistence
        download_obico
        install_dependencies
        fix_permissions_scripts
        create_config
        link_printer
        setup_autostart
        restart_moonraker
        verify
        echo ""
        log "Installation complete! Check your Obico server to confirm the printer is online."
        echo ""
        warn "Note: You will see a 'Webcam Streaming Failed (Janus)' warning in Obico."
        warn "This is normal and expected — Janus is not available on the U1."
        warn "AI failure detection works fine without it via snapshot mode."
        echo ""
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
        echo ""
        echo "  install    - Install and configure moonraker-obico (default)"
        echo "  uninstall  - Remove moonraker-obico"
        echo "  restore    - Restore after a firmware upgrade"
        exit 1
        ;;
esac
