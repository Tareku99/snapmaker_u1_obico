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
    EXTENDED_CONFIG="$printer/extended"
    MOONRAKER_EXTRA_CFG="$EXTENDED_CONFIG/moonraker/05_obico.cfg"
    MOONRAKER_COMPONENT="$printer/components/obico_starter.py"
    MOONRAKER_INIT="$printer/restart"
    PERSISTENCE_MARKER="$printer/oem/.debug"

    id() { printf '0\n'; }
    chown() { :; }
    pgrep() { return 1; }
    sleep() { :; }
    ip() { printf '    inet 192.0.2.10/24 scope global eth0\n'; }
    curl() {
        while [ "$#" -gt 0 ]; do
            if [ "$1" = -o ]; then
                if [ -f "$printer/fail-download" ]; then return 1; fi
                cp "$test_root/source.tar.gz" "$2"
                return
            fi
            shift
        done
        [ ! -f "$printer/fail-http" ]
    }
    python3() {
        if [ "$1" = -c ]; then return 0; fi
        [ "$1" = -m ] && [ "$2" = venv ] && [ "$3" = "$OBICO_VENV" ] ||
            return 1
        mkdir -p "$3/bin"
        cat > "$3/bin/python" <<EOF
#!/bin/bash
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

printf 'Installer regression checks passed.\n'
