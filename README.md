# Aura Registry Proxy

An optional RFC-005 read-through proxy written in Aura and using
[`auraspace/pulse`](https://github.com/auraspace/pulse) for HTTP routing.

The proxy is read-only. A package is published by pushing an immutable
`vX.Y.Z` tag to its Git origin; this service only serves/cache-equivalent
representations of that origin.

## RFC-005 Contract

```text
GET /<module>/@v/list
GET /<module>/@v/<version>.info
GET /<module>/@v/<version>.mod
GET /<module>/@v/<version>.zip
GET /healthz
```

For this implementation, `<module>` is exactly `<owner>/<repo>`. The proxy
accepts `GET` and `HEAD` for package objects and returns `405` for other
methods. Metadata uses `application/json` (`.info`) or UTF-8 text (`list`,
`.mod`); archives use `application/zip`.

The cache is lazy and starts empty. On a miss, the optional
`AURA_REGISTRY_UPSTREAM` is queried with the same object path. A successful
response is written atomically below `AURA_REGISTRY_ROOT`; later hits are
served locally without contacting upstream. If the cache cannot be written,
the fetched object is still served and the next request retries the fetch.

Every package response includes `X-Aura-Origin` with the canonical GitHub
origin and `X-Aura-Object` with the requested object path. These headers are
metadata only; they do not turn the proxy into the package owner.

The proxy does not publish packages, resolve semver, rewrite module identity,
or provide an upload API. Clients still resolve an immutable tag/commit and
pin `version`, `source`, `rev`, and `checksum` in `aura.lock`.

The example uses the binary `std.bytes.readFileBytes` and
`std.http.Response.setBodyBytes` APIs for source archives. Those APIs were
added to the compiler/runtime boundary specifically so `.zip` objects do not
pass through Aura `String` and lose embedded NUL bytes.

## Cache Layout

The on-disk layout mirrors the HTTP path:

```text
<AURA_REGISTRY_ROOT>/
  <owner>/<repo>/@v/
    list
    <version>.info
    <version>.mod
    <version>.zip
```

Directories are created only when the first object for a module is fetched.
Cache files are replaced atomically, so readers never need to observe a
partially written object. The default root is `./registry`.

## Optional Fixture/Bootstrap Tooling

```sh
./scripts/sync-github.sh
```

This is not required for normal startup. It downloads manifests and source
archives for `dotenv`, `pulse`, `pg`, and `sqlite` into a local fixture tree so
the proxy can be tested without an upstream. `dotenv` and `pulse` use their
immutable `v1.0.0` tags. `pg` and `sqlite` currently have no Git tag, so the
script labels their `main` snapshots as development fixtures rather than
pretending they are immutable releases.

## Build and Run

Build from an Aura checkout. Set `AURA_REPO` to its absolute path if the
proxy repo and Aura repo are siblings:

```sh
AURA_REPO=/path/to/auraspace/aura
AURA_STD="$AURA_REPO/std" cargo run --manifest-path "$AURA_REPO/Cargo.toml" \
  -p aura-cli -- build . -o /tmp/aura-registry-proxy --rebuild-runtime
cache_dir=$(mktemp -d)
AURA_REGISTRY_ROOT="$cache_dir" \
AURA_REGISTRY_UPSTREAM="https://registry.example.test" \
/tmp/aura-registry-proxy 8080
```

`AURA_REGISTRY_UPSTREAM` must be another RFC-005 origin serving the same
`/<owner>/<repo>/@v/<object>` paths. It accepts `host:port` for plain HTTP or
`https://host[:port]` for verified OpenSSL TLS. The upstream response must be
bounded to the proxy's 64 MiB object limit.

The first request for an object fetches it from the upstream and atomically
materializes it under `cache_dir`. Later requests use that cached object. Use
`./scripts/sync-github.sh` first only when you want a local, pre-populated
fixture and run with `AURA_REGISTRY_UPSTREAM` unset.

Then:

```sh
curl -i http://127.0.0.1:8080/healthz
curl -i http://127.0.0.1:8080/auraspace/dotenv/@v/list
curl -i http://127.0.0.1:8080/auraspace/pulse/@v/v1.0.0.info
curl -i http://127.0.0.1:8080/auraspace/pulse/@v/v1.0.0.mod
```

Run the local-cache and upstream binary smoke test after building:

```sh
./scripts/smoke.sh /tmp/aura-registry-proxy
```

## Current compiler/runtime boundary

- Pulse routing supports literal and `:param` segments; this example uses
  the fixed `owner/repo/@v/object` shape.
- `std.http.Response.setBodyBytes`, `std.bytes.readFileBytes`, and
  `std.http.getBytes` provide the binary archive path.
- `std.fs.ensureDirectory` plus atomic text/binary file writes make cache
  population safe when the configured root starts empty.
- The C and LLVM backends use the same bounded runtime HTTP client for
  upstream binary read-through: HTTP/1.1, `Content-Length` or chunked transfer
  framing, and a 64 MiB maximum.
- Binary compiler intrinsics and filesystem cache operations are available to
  both native backends through the shared runtime/platform contract.
- `std.fs` has file/path inspection plus the directory-create operation used to
  create cache parents lazily on the first upstream miss.
- `std.http` binary client transport is intentionally bounded and one-shot;
  each request closes its connection after the response body is consumed.

## More Detail

- [RFC-005 proxy protocol and operational notes](docs/rfc-005-proxy.md)
- [Aura package manager RFC](https://github.com/auraspace/aura/blob/main/docs/rfc/RFC-005-package-manager.md)
