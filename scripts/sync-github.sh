#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/registry"
mkdir -p "$root"

download_repo() {
    repo="$1"
    version="$2"
    ref="$3"
    dir="$root/auraspace/$repo/@v"
    mkdir -p "$dir"

    curl --fail --silent --show-error --location \
        "https://raw.githubusercontent.com/auraspace/$repo/$ref/aura.toml" \
        -o "$dir/$version.mod"
    printf '%s\n' "$version" > "$dir/list"
    commit="$(curl --fail --silent --show-error --location \
        "https://api.github.com/repos/auraspace/$repo/commits/$ref" \
        | sed -n 's/.*"sha": "\([0-9a-f]*\)".*/\1/p' | head -n 1)"
    [ -n "$commit" ]
    printf '{"Version":"%s","Origin":"https://github.com/auraspace/%s","Rev":"%s"}\n' \
        "$version" "$repo" "$commit" > "$dir/$version.info"

    archive="$dir/$version.zip"
    curl --fail --silent --show-error --location \
        "https://codeload.github.com/auraspace/$repo/zip/$ref" -o "$archive"
}

download_repo dotenv v1.0.0 v1.0.0
download_repo pulse v1.0.0 v1.0.0
download_repo pg v0.1.0-main main
download_repo sqlite v0.1.0-main main

echo "registry fixtures written to $root"
