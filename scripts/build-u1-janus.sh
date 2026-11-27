#!/bin/bash
set -euo pipefail

# Use a Debian 12 ARM64 userspace so the bundle runs on the U1's glibc 2.38.
image="public.ecr.aws/docker/library/debian@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e"
if [ "$#" -ne 1 ]; then
    printf 'Usage: bash scripts/build-u1-janus.sh OUTPUT_DIRECTORY\n' >&2
    exit 1
fi
if [ "${OBICO_JANUS_BUILD_CONTAINER:-}" = check ]; then
    smoke=$(mktemp -d)
    tar -xzf "$1/obico-janus-u1-aarch64.tar.gz" -C "$smoke"
    mkdir "$smoke/etc"
    cat > "$smoke/etc/janus.jcfg" <<EOF
general: {
    plugins_folder = "$smoke/lib/janus/plugins"
    transports_folder = "$smoke/lib/janus/transports"
}
EOF
    cat > "$smoke/etc/janus.transport.websockets.jcfg" <<'EOF'
general: {
    ws = true
    ws_port = 18794
    ws_ip = "127.0.0.1"
    wss = false
}
EOF
    printf 'general: {}\n' > "$smoke/etc/janus.plugin.streaming.jcfg"
    result=0
    timeout 5 env LD_LIBRARY_PATH="$smoke/lib" "$smoke/bin/janus" --configs-folder "$smoke/etc" > "$smoke/janus.log" 2>&1 ||
        result=$?
    cat "$smoke/janus.log"
    [ "$result" -eq 124 ]
    grep -iq 'streaming plugin initialized' "$smoke/janus.log"
    grep -iq 'websockets.*initialized' "$smoke/janus.log"
    exit
fi
if [ "${OBICO_JANUS_BUILD_CONTAINER:-}" != 1 ]; then
    mkdir -p -- "$1"
    output=$(cd "$1" && pwd)
    script_dir=$(cd "$(dirname "$0")" && pwd)
    docker run --rm --platform linux/arm64 \
        -e OBICO_JANUS_BUILD_CONTAINER=1 \
        --mount "type=bind,source=$script_dir,target=/scripts,readonly" \
        --mount "type=bind,source=$output,target=/output" \
        "$image" bash /scripts/build-u1-janus.sh /output
    exec docker run --rm --platform linux/arm64 \
        -e OBICO_JANUS_BUILD_CONTAINER=check \
        --mount "type=bind,source=$script_dir,target=/scripts,readonly" \
        --mount "type=bind,source=$output,target=/output,readonly" \
        "$image" bash /scripts/build-u1-janus.sh /output
fi

source_commit=1f0b75cac1c9ad819ee4c2a905a2c65b00b82cde
source_hash=5a1a426d59343a294475b8df9f3d94438dd95f7eadc2f225860f089f073bc6a8
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install --no-install-recommends \
    autoconf automake build-essential ca-certificates curl libconfig-dev libcurl4-openssl-dev \
    libglib2.0-dev libjansson-dev libnice-dev libsrtp2-dev libssl-dev libtool \
    libusrsctp-dev libwebsockets-dev pkg-config zlib1g-dev

work=$(mktemp -d)
curl -fsSL --retry 2 "https://codeload.github.com/meetecho/janus-gateway/tar.gz/$source_commit" -o "$work/janus-source.tar.gz"
printf '%s  %s\n' "$source_hash" "$work/janus-source.tar.gz" | sha256sum -c -
mkdir "$work/source" "$work/runtime"
tar -xzf "$work/janus-source.tar.gz" --strip-components=1 -C "$work/source"
cd "$work/source"
sh autogen.sh
./configure --prefix=/usr --disable-all-plugins --enable-plugin-streaming \
    --disable-all-transports --enable-websockets --disable-all-handlers --disable-all-loggers
make -j 6
make install DESTDIR="$work/install"

runtime="$work/runtime"
mkdir -p "$runtime/bin" "$runtime/lib/janus/plugins" "$runtime/lib/janus/transports" "$runtime/licenses"
install -m 755 "$work/install/usr/bin/janus" "$runtime/bin/janus"
install -m 755 "$work/install/usr/lib/janus/plugins/libjanus_streaming.so" "$runtime/lib/janus/plugins/"
install -m 755 "$work/install/usr/lib/janus/transports/libjanus_websockets.so" "$runtime/lib/janus/transports/"
cp COPYING "$runtime/licenses/janus-gateway"

objects=("$runtime/bin/janus" "$runtime/lib/janus/plugins/libjanus_streaming.so"
    "$runtime/lib/janus/transports/libjanus_websockets.so")
# Debian's libsrtp uses NSS. These modules are loaded at runtime and do not
# appear in the Janus binary's linked-library list.
if ldd "$runtime/bin/janus" | grep 'libnss3\.so' >/dev/null; then
    libdir="/usr/lib/$(gcc -print-multiarch)"
    for module in libsoftokn3 libfreebl3 libfreeblpriv3; do
        cp -L "$libdir/$module.so" "$runtime/lib/"
        if [ -f "$libdir/$module.chk" ]; then cp -L "$libdir/$module.chk" "$runtime/lib/"; fi
        objects+=("$libdir/$module.so")
    done
fi
for object in "${objects[@]}"; do
    ldd "$object"
done > "$work/linked-libraries"
if grep -F 'not found' "$work/linked-libraries"; then
    exit 1
fi
printf 'Janus 1.4.3\nSource: https://github.com/meetecho/janus-gateway/commit/%s\nSource archive SHA-256: %s\n' \
    "$source_commit" "$source_hash" > "$runtime/BUILD-INFO"
awk '$2 == "=>" && $3 ~ /^\// { print $1, $3 }' "$work/linked-libraries" |
    sort -u |
    while read -r name library; do
        case "$name" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libresolv.so.2|libutil.so.1|libanl.so.1) continue ;;
        esac
        cp -L "$library" "$runtime/lib/$name"
        owner=$(dpkg-query -S "$library" 2>/dev/null ||
            dpkg-query -S "$(readlink -f "$library")" 2>/dev/null ||
            dpkg-query -S "/usr$library" 2>/dev/null)
        package=${owner%%: *}
        dpkg-query -W -f='${binary:Package}\t${Version}\t${source:Package}\t${source:Version}\n' "$package"
        copyright="/usr/share/doc/${package%%:*}/copyright"
        if [ -f "$copyright" ]; then cp -L "$copyright" "$runtime/licenses/${package%%:*}"; fi
    done | sort -u > "$runtime/PACKAGES"

LD_LIBRARY_PATH="$runtime/lib" "$runtime/bin/janus" --version
tar -czf "$1/obico-janus-u1-aarch64.tar.gz" -C "$runtime" bin lib licenses BUILD-INFO PACKAGES
cp "$work/janus-source.tar.gz" "$1/janus-1.4.3-source.tar.gz"
cd "$1"
sha256sum obico-janus-u1-aarch64.tar.gz > obico-janus-u1-aarch64.tar.gz.sha256
