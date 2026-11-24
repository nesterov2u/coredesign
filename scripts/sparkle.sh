#!/bin/bash

# Source this file to share the same pinned framework between build and release.
sparkle_version=2.10.1
sparkle_sha256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
sparkle_cache="${COREDESIGN_BUILD_CACHE:-.build}/sparkle-$sparkle_version"
sparkle_url="https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz"

prepare_sparkle() {
    if [[ -d "$sparkle_cache/Sparkle.framework" ]]; then return; fi
    local staging archive
    mkdir -p "$(dirname "$sparkle_cache")"
    staging="$(mktemp -d "${sparkle_cache}.XXXXXX")"
    archive="$staging/sparkle.tar.xz"
    if [[ -n "${SPARKLE_ARCHIVE:-}" ]]; then
        cp "$SPARKLE_ARCHIVE" "$archive"
    else
        curl --fail --location --silent --show-error --retry 2 "$sparkle_url" -o "$archive"
    fi
    printf '%s  %s\n' "$sparkle_sha256" "$archive" | shasum -a 256 -c
    tar -xf "$archive" -C "$staging" Sparkle.framework LICENSE
    mkdir -p "$sparkle_cache"
    ditto "$staging/Sparkle.framework" "$sparkle_cache/Sparkle.framework"
    cp "$staging/LICENSE" "$sparkle_cache/LICENSE"
    rm -rf "$staging"
}
