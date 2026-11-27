#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
installer="$repo_dir/obico-install.sh"
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

bash -n "$installer"
bash "$installer" --help > "$test_root/help"
grep -Fq 'Usage:' "$test_root/help"
if bash "$installer" --dry-run update --typo; then fail "unknown option accepted"; fi
if bash "$installer" --dry-run backup v4.0.0; then fail "unexpected version accepted"; fi
if bash "$installer" --dry-run update --no-link; then fail "install-only flag accepted"; fi

# Redirect printer paths into a fixture and stub the root check, network and
# printer services. The installer still moves, extracts and copies real files.
invoke() (
    source "$installer"
    USERDATA="$printer/userdata"
    OBICO_DIR="$USERDATA/moonraker-src"
    OBICO_LOGS="$USERDATA/obico-logs"
    OBICO_VENV="$USERDATA/obico-venv"
    OBICO_CFG="$OBICO_DIR/moonraker-obico.cfg"
    OBICO_VERSION_CFG="$USERDATA/obico-version.cfg"
    BACKUP_DIR="$USERDATA/obico-backup"
    INSTALL_LOCK="$USERDATA/.obico-installer.lock"
    JANUS_DIR="$USERDATA/obico-janus"
    EXTENDED_CONFIG="$printer/extended"
    MOONRAKER_EXTRA_CFG="$EXTENDED_CONFIG/moonraker/05_obico.cfg"
    MOONRAKER_COMPONENT="$printer/components/obico_starter.py"
    MOONRAKER_INIT="$printer/restart"
    PERSISTENCE_MARKER="$printer/oem/.debug"
    if [ -f "$test_root/janus.tar.gz.sha256" ]; then
        read -r JANUS_RELEASE_SHA256 _ < "$test_root/janus.tar.gz.sha256"
    fi

    id() { printf '0\n'; }
    chown() { :; }
    pgrep() { return 1; }
    sleep() { :; }
    ip() { printf '    inet 192.0.2.10/24 scope global eth0\n'; }
    check_native_video_platform() { :; }
    curl() {
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -o ]; then
                if [ -f "$printer/fail-download" ]; then return 1; fi
                if [[ "$2" = */janus.tar.gz ]]; then
                    cp "$test_root/janus.tar.gz" "$2"
                else
                    cp "$test_root/source.tar.gz" "$2"
                fi
                return
            fi
            shift
        done
        [ ! -f "$printer/fail-http" ]
    }
    python3() {
        if [ "$1" = -c ]; then return 0; fi
        if [ "$1" = - ]; then command python3 "$@"; return; fi
        [ "$1" = -m ] && [ "$2" = venv ] && [ "$3" = "$OBICO_VENV" ] ||
            return 1
        mkdir -p "$3/bin"
        cat > "$3/bin/python" <<EOF
#!/bin/bash
if [ "\$1" = -c ]; then
    printf 'NA.buildroot.2024.64-bit\n'
    exit 0
fi
[ ! -f "$printer/fail-pip" ]
EOF
        chmod +x "$3/bin/python"
    }
    main "$@"
)

run() {
    # Keep errexit enabled in the child even when the caller expects failure.
    bash -e -c 'source "$1"; shift; invoke "$@"' _ "$test_root/fixture.sh" "$@"
}
declare -f invoke > "$test_root/fixture.sh"
export installer test_root

mkdir -p "$test_root/archive/obico/moonraker_obico"
touch "$test_root/archive/obico/requirements.txt"
cat > "$test_root/archive/obico/moonraker_obico/webcam_stream.py" <<'EOF'
def h264_copy(self, webcam):
    self.start_ffmpeg(1234, f'-re -i {webcam.h264_http_url} -c:v copy')
EOF
tar -czf "$test_root/source.tar.gz" -C "$test_root/archive" obico

new_printer() {
    printer="$test_root/$1"
    export printer
    mkdir -p "$printer/userdata" "$printer/oem" "$printer/extended/moonraker" "$printer/components"
    touch "$printer/extended/extended2.cfg"
    cat > "$printer/restart" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$printer/restarts"
EOF
    chmod +x "$printer/restart"
}

existing_install() {
    mkdir -p "$printer/userdata/moonraker-src" "$printer/userdata/obico-venv/bin" "$printer/userdata/obico-logs"
    printf '[server]\nauth_token = existing-token\n' > "$printer/userdata/moonraker-src/moonraker-obico.cfg"
    printf 'old source\n' > "$printer/userdata/moonraker-src/old-source"
    printf 'old python\n' > "$printer/userdata/obico-venv/bin/python"
    printf 'old logs\n' > "$printer/userdata/obico-logs/moonraker-obico.log"
    printf 'version = old\n' > "$printer/userdata/obico-version.cfg"
    printf 'old component\n' > "$printer/components/obico_starter.py"
    printf '[obico_starter]\n' > "$printer/extended/moonraker/05_obico.cfg"
}

assert_old_install() {
    grep -Fqx 'auth_token = existing-token' "$printer/userdata/moonraker-src/moonraker-obico.cfg"
    grep -Fqx 'old source' "$printer/userdata/moonraker-src/old-source"
    grep -Fqx 'old python' "$printer/userdata/obico-venv/bin/python"
    grep -Fqx 'version = old' "$printer/userdata/obico-version.cfg"
    grep -Fqx 'old component' "$printer/components/obico_starter.py"
    grep -Fqx '[obico_starter]' "$printer/extended/moonraker/05_obico.cfg"
    [ -z "$(find "$printer/userdata" -maxdepth 1 -name '.obico-install*' -print)" ]
}

new_printer dry-run
existing_install
cp -a "$printer" "$test_root/before"
for command in install update uninstall backup restore; do
    run --dry-run "$command" </dev/null
done
diff -r "$test_root/before" "$printer"

new_printer fresh
printf '1\n' | run install --no-link --no-autostart
grep -Fqx 'url = https://app.obico.io' "$printer/userdata/moonraker-src/moonraker-obico.cfg"
[ -x "$printer/userdata/obico-venv/bin/python" ]
[ -f "$printer/oem/.debug" ]
[ ! -f "$printer/extended/moonraker/05_obico.cfg" ]
run update v4.0.0
[ ! -f "$printer/extended/moonraker/05_obico.cfg" ]

new_printer existing
existing_install
mkdir "$printer/userdata/.obico-installer.lock"
if run update; then fail "second operation acquired the lock"; fi
rmdir "$printer/userdata/.obico-installer.lock"
assert_old_install

if printf 'n\n' | run install; then fail "reinstall ignored cancellation"; fi
assert_old_install

for fault in download pip http; do
    touch "$printer/fail-$fault"
    if run update v4.0.0; then fail "update succeeded despite $fault failure"; fi
    assert_old_install
    rm -- "$printer/fail-$fault"
done

run update v4.0.0
grep -Fqx 'auth_token = existing-token' "$printer/userdata/moonraker-src/moonraker-obico.cfg"
grep -Fqx 'version = v4.0.0' "$printer/userdata/obico-version.cfg"
grep -Fqx 'old component' "$printer/components/obico_starter.py"
[ ! -e "$printer/userdata/moonraker-src/old-source" ]
[ -x "$printer/userdata/obico-venv/bin/python" ]

rm -- "$printer/components/obico_starter.py"
run restore
python3 -m py_compile "$printer/components/obico_starter.py"

touch "$printer/userdata/obico-backup"
if printf 'y\n' | run uninstall --keep-config; then fail "uninstall continued after backup failed"; fi
grep -Fqx 'auth_token = existing-token' "$printer/userdata/moonraker-src/moonraker-obico.cfg"
[ -x "$printer/userdata/obico-venv/bin/python" ]
rm -- "$printer/userdata/obico-backup"

printf 'y\n' | run uninstall --keep-config
grep -Fqx 'auth_token = existing-token' "$printer/userdata/obico-backup/moonraker-obico.cfg"
[ "$(stat -c '%a' "$printer/userdata/obico-backup")" = 700 ]
[ -f "$printer/userdata/obico-logs/moonraker-obico.log" ]
[ ! -e "$printer/userdata/moonraker-src" ]
[ ! -e "$printer/userdata/obico-venv" ]
[ ! -e "$printer/components/obico_starter.py" ]
[ ! -e "$printer/extended/moonraker/05_obico.cfg" ]

new_printer backup
existing_install
rm -rf -- "$printer/userdata/obico-logs"
run backup
grep -Fqx 'auth_token = existing-token' "$printer/userdata/obico-backup/moonraker-obico.cfg"
grep -Fqx 'version = old' "$printer/userdata/obico-backup/obico-version.cfg"

janus_fixture="$test_root/janus"
mkdir -p "$janus_fixture/bin" "$janus_fixture/lib/janus/plugins" "$janus_fixture/lib/janus/transports"
printf '#!/bin/bash\nprintf "Janus test bundle\\n"\n' > "$janus_fixture/bin/janus"
chmod +x "$janus_fixture/bin/janus"
touch "$janus_fixture/lib/janus/plugins/libjanus_streaming.so" "$janus_fixture/lib/janus/transports/libjanus_websockets.so"
janus_archive="$test_root/janus.tar.gz"
tar -czf "$janus_archive" -C "$janus_fixture" bin lib
sha256sum "$janus_archive" > "$janus_archive.sha256"

new_printer native
printf '2\nhttp://192.0.2.20:3334\n' | run install --no-link --no-autostart --native-video
native_config="$printer/userdata/moonraker-src/moonraker-obico.cfg"
variant_path="$printer/userdata/moonraker-src/moonraker_obico/bin/janus/precomplied/NA.buildroot.2024.64-bit"
grep -Fqx 'native_video = true' "$printer/userdata/obico-version.cfg"
grep -Fqx 'stream_mode = h264_copy' "$native_config"
grep -Fqx 'h264_http_url = http://127.0.0.1/webcam/stream.h264' "$native_config"
[ "$(readlink "$variant_path")" = "$printer/userdata/obico-janus" ]
grep -Fq "f'-i {webcam.h264_http_url} -c:v copy'" "$printer/userdata/moonraker-src/moonraker_obico/webcam_stream.py"
cp "$native_config" "$test_root/native-before.cfg"
run update
cmp "$native_config" "$test_root/native-before.cfg"
[ "$(readlink "$variant_path")" = "$printer/userdata/obico-janus" ]

rm -- "$variant_path"
run restore
[ "$(readlink "$variant_path")" = "$printer/userdata/obico-janus" ]

cat > "$printer/components/obico_starter.py" <<EOF
class LegacyStarter:
    def start(self):
        subprocess.Popen(
            ["$printer/userdata/obico-venv/bin/python", "-m", "moonraker_obico.app"])

    async def close(self):
        if self.process is not None:
            self.process.terminate()
EOF
printf '[obico_starter]\n' > "$printer/extended/moonraker/05_obico.cfg"
run update
grep -Fq 'start_new_session=True' "$printer/components/obico_starter.py"
cmp "$native_config" "$test_root/native-before.cfg"

python3 - "$printer/components/obico_starter.py" "$test_root/child.pid" <<'PY'
import asyncio
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys

starter_type = runpy.run_path(sys.argv[1])["ObicoStarter"]
class Config:
    def get_server(self):
        return self

    def register_event_handler(self, name, callback):
        pass

async def check():
    starter = starter_type(Config())
    child_file = Path(sys.argv[2])
    leader = subprocess.Popen([
        sys.executable, "-c",
        "import pathlib, subprocess, sys, time; "
        "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
        "pathlib.Path(sys.argv[1]).write_text(str(child.pid)); time.sleep(30)",
        str(child_file),
    ], start_new_session=True)
    try:
        for _ in range(50):
            if child_file.exists() and child_file.stat().st_size:
                break
            await asyncio.sleep(0.02)
        child = int(child_file.read_text())
        starter.process = leader
        await starter.close()
        status = Path(f"/proc/{child}/stat")
        try:
            state = status.read_text().rsplit(") ", 1)[1].split()[0]
        except FileNotFoundError:
            state = "exited"
        assert state in {"Z", "exited"}, f"Obico child {child} was left running"
        assert leader.poll() is not None
    finally:
        try:
            os.killpg(leader.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        leader.wait(timeout=2)

asyncio.run(check())
PY

touch "$printer/userdata/obico-janus/previous-runtime"
touch "$printer/fail-http"
if run update --janus-bundle "$janus_archive"; then fail "native update succeeded despite Moonraker failure"; fi
[ -f "$printer/userdata/obico-janus/previous-runtime" ]
cmp "$native_config" "$test_root/native-before.cfg"
[ "$(readlink "$variant_path")" = "$printer/userdata/obico-janus" ]
rm -- "$printer/fail-http"

new_printer native-cloud
if printf '1\n' | run install --no-link --janus-bundle "$janus_archive"; then
    fail "self-hosted native video settings were applied to Obico Cloud"
fi
[ ! -e "$printer/userdata/obico-janus" ]
[ ! -e "$printer/userdata/moonraker-src" ]
printer="$test_root/native"
export printer

printf '%064d\n' 0 > "$janus_archive.sha256"
if run update --janus-bundle "$janus_archive"; then fail "unverified Janus archive accepted"; fi
cmp "$native_config" "$test_root/native-before.cfg"
[ -x "$printer/userdata/obico-janus/bin/janus" ]

printf 'y\n' | run uninstall --keep-config
[ ! -e "$printer/userdata/obico-janus" ]
grep -Fqx 'stream_mode = h264_copy' "$printer/userdata/obico-backup/moonraker-obico.cfg"

printf 'Installer regression checks passed.\n'
