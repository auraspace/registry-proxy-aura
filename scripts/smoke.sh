#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
proxy_bin=${1:-${AURA_REGISTRY_PROXY_BIN:-}}
if [ -z "$proxy_bin" ] || [ ! -x "$proxy_bin" ]; then
    echo "usage: $0 /path/to/registry-proxy-aura" >&2
    exit 2
fi

proxy_port=${AURA_PROXY_SMOKE_PORT:-18180}
upstream_port=${AURA_PROXY_SMOKE_UPSTREAM_PORT:-18181}
empty_root=$(mktemp -d "${TMPDIR:-/tmp}/aura-registry-smoke.XXXXXX")
upstream_log=$(mktemp "${TMPDIR:-/tmp}/aura-registry-upstream.XXXXXX")
proxy_log=$(mktemp "${TMPDIR:-/tmp}/aura-registry-proxy.XXXXXX")
fixture_root="$script_dir/registry"

for fixture in \
    "$fixture_root/auraspace/pulse/@v/list" \
    "$fixture_root/auraspace/pulse/@v/v1.0.0.info" \
    "$fixture_root/auraspace/pulse/@v/v1.0.0.mod" \
    "$fixture_root/auraspace/pulse/@v/v1.0.0.zip"; do
    if [ ! -f "$fixture" ]; then
        echo "missing fixture: $fixture (run scripts/sync-github.sh first)" >&2
        exit 1
    fi
done

cleanup() {
    kill "${proxy_pid:-}" "${upstream_pid:-}" 2>/dev/null || true
    wait "${proxy_pid:-}" "${upstream_pid:-}" 2>/dev/null || true
    rm -rf "$empty_root" "$upstream_log" "$proxy_log"
}
trap cleanup EXIT INT TERM

python3 "$script_dir/scripts/chunked-server.py" "$fixture_root" "$upstream_port" >"$upstream_log" 2>&1 &
upstream_pid=$!
AURA_REGISTRY_ROOT="$empty_root" \
    AURA_REGISTRY_UPSTREAM="127.0.0.1:${upstream_port}" \
    "$proxy_bin" "$proxy_port" >"$proxy_log" 2>&1 &
proxy_pid=$!
sleep 1
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/healthz" | grep -qx 'ok'
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/list" \
    -o "$empty_root/upstream.list"
cmp "$fixture_root/auraspace/pulse/@v/list" "$empty_root/upstream.list"
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.info" \
    -o "$empty_root/upstream.info"
cmp "$fixture_root/auraspace/pulse/@v/v1.0.0.info" "$empty_root/upstream.info"
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.mod" \
    -o "$empty_root/upstream.mod"
cmp "$fixture_root/auraspace/pulse/@v/v1.0.0.mod" "$empty_root/upstream.mod"
curl --fail --silent --show-error --head \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.zip" | grep -q 'HTTP/.* 200'
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.zip" \
    -o "$empty_root/upstream.zip"
cmp "$fixture_root/auraspace/pulse/@v/v1.0.0.zip" "$empty_root/upstream.zip"
[ -f "$empty_root/auraspace/pulse/@v/list" ]
[ -f "$empty_root/auraspace/pulse/@v/v1.0.0.info" ]
[ -f "$empty_root/auraspace/pulse/@v/v1.0.0.mod" ]
[ -f "$empty_root/auraspace/pulse/@v/v1.0.0.zip" ]
curl --silent --show-error --output /dev/null --write-out '%{http_code}\n' \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/missing.info" | grep -qx '404'
kill "$proxy_pid" 2>/dev/null || true
wait "$proxy_pid" 2>/dev/null || true

kill "$upstream_pid" 2>/dev/null || true
wait "$upstream_pid" 2>/dev/null || true
AURA_REGISTRY_ROOT="$empty_root" \
    "$proxy_bin" "$proxy_port" >"$proxy_log" 2>&1 &
proxy_pid=$!
sleep 1
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.info" \
    -o "$empty_root/cache-hit.info"
cmp "$fixture_root/auraspace/pulse/@v/v1.0.0.info" "$empty_root/cache-hit.info"
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.mod" \
    -o "$empty_root/cache-hit.mod"
cmp "$fixture_root/auraspace/pulse/@v/v1.0.0.mod" "$empty_root/cache-hit.mod"
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/v1.0.0.zip" \
    -o "$empty_root/cache-hit.zip"
cmp "$fixture_root/auraspace/pulse/@v/v1.0.0.zip" "$empty_root/cache-hit.zip"
curl --fail --silent --show-error \
    "http://127.0.0.1:${proxy_port}/auraspace/pulse/@v/list" \
    -o "$empty_root/cache-hit.list"
cmp "$fixture_root/auraspace/pulse/@v/list" "$empty_root/cache-hit.list"

echo "registry proxy smoke: ok"
