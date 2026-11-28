#!/bin/bash
set -euo pipefail

# Collect the exact Debian sources for the libraries in a built Janus archive.
if [ "$#" -ne 1 ]; then
    printf 'Usage: bash scripts/collect-janus-sources.sh BUNDLE_DIRECTORY\n' >&2
    exit 1
fi
if [ "${OBICO_JANUS_SOURCE_CONTAINER:-}" != 1 ]; then
    output=$(cd "$1" && pwd)
    script_dir=$(cd "$(dirname "$0")" && pwd)
    image="public.ecr.aws/docker/library/debian@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e"
    exec docker run --rm --platform linux/arm64 -e OBICO_JANUS_SOURCE_CONTAINER=1 \
        --mount "type=bind,source=$script_dir,target=/scripts,readonly" \
        --mount "type=bind,source=$output,target=/output" \
        "$image" bash /scripts/collect-janus-sources.sh /output
fi

output="$1"
work=$(mktemp -d)
tar -xOf "$output/obico-janus-u1-aarch64.tar.gz" PACKAGES > "$work/PACKAGES"
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
apt-get -qq update
mkdir "$work/debian-sources"
cd "$work/debian-sources"
cut -f3,4 "$work/PACKAGES" | sort -u |
    while IFS=$'\t' read -r name version; do
        printf 'Downloading source for %s %s\n' "$name" "$version"
        apt-get -qq source --download-only "$name=$version"
    done
cp "$work/PACKAGES" .
tar -cf "$output/obico-janus-u1-debian-sources.tar" -C "$work" debian-sources
