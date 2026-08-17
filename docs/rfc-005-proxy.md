# RFC-005 Proxy Notes

This document describes the behavior of this example service. It is an
implementation guide for the optional proxy/cache described by RFC-005; it
does not add a new publication or package-identity mechanism.

## 1. Origin Model

The package origin is a Git repository. A maintainer publishes a release by
creating and pushing an immutable semver tag, for example `v1.0.0`:

```text
validate aura.toml
  -> commit package sources
  -> git tag v1.0.0
  -> git push origin v1.0.0
```

The proxy may mirror the read shapes below, but it must preserve the origin
semantics. It does not accept uploads, create tags, choose versions, or act as
an index of package ownership.

## 2. HTTP Read Contract

The implementation supports these routes:

| Route | Meaning | Content type |
| --- | --- | --- |
| `/<owner>/<repo>/@v/list` | Available versions | `text/plain; charset=utf-8` |
| `/<owner>/<repo>/@v/<version>.info` | Version, origin, and revision metadata | `application/json` |
| `/<owner>/<repo>/@v/<version>.mod` | The tagged `aura.toml` | `text/plain; charset=utf-8` |
| `/<owner>/<repo>/@v/<version>.zip` | Source archive at the tagged revision | `application/zip` |
| `/healthz` | Process health | `text/plain` |

`<owner>`, `<repo>`, and the object name must be one path segment. `.` and
`..`, slash characters, and backslash characters are rejected. Object names
are limited to `list`, `.info`, `.mod`, and `.zip` forms. This validation keeps
the URL from escaping the configured cache root.

Package routes accept `GET` and `HEAD`. `HEAD` performs the same cache lookup
and upstream behavior but does not return a response body. Unsupported
methods receive `405`.

Successful package responses include:

```text
X-Aura-Origin: https://github.com/<owner>/<repo>
X-Aura-Object: /<owner>/<repo>/@v/<object>
```

These headers are informational and do not replace the origin or lockfile
verification performed by a client.

## 3. Lazy Read-Through Cache

The cache is intentionally lazy:

```text
request
  -> validate method and path
  -> local cache hit? serve bytes
  -> cache miss + upstream configured? fetch the same object path
  -> validate bounded response
  -> create parent directory
  -> atomically write cache file
  -> serve fetched bytes
```

The default root is `registry`; `AURA_REGISTRY_ROOT` overrides it. The cache
path is derived directly from the validated request:

```text
<AURA_REGISTRY_ROOT>/<owner>/<repo>/@v/<object>
```

No directories or files are created at startup. This allows a new deployment
to start with an empty volume and only materialize objects that are requested.

The first request may fetch from upstream. Concurrent requests may both fetch
the same missing object; each write is atomic, and either valid result is
equivalent. A cache write failure does not fail an otherwise valid upstream
response; the object is served and a later request can retry population.

If upstream is unset, a cache miss returns `404`. An upstream transport or
response failure returns `502` for the archive path and `404` for metadata.

## 4. Upstream and Limits

`AURA_REGISTRY_UPSTREAM` is an origin base URL. The proxy appends the exact
object path, so an upstream for `auraspace/pulse` receives:

```text
/auraspace/pulse/@v/v1.0.0.zip
```

The binary client supports HTTP/1.1 responses with either `Content-Length` or
chunked transfer encoding. It is one-shot and closes the connection after the
body is consumed. Objects are bounded at 64 MiB. HTTPS uses verified OpenSSL
TLS; `host:port` is available for local plain-HTTP fixtures.

The proxy does not trust an upstream to define the package identity. The Aura
client must still resolve the selected tag to a commit, verify the source
checksum, and pin the immutable `rev` and `checksum` in `aura.lock`.

## 5. Local Verification

Populate deterministic fixtures from the public repositories:

```sh
./scripts/sync-github.sh
```

Build the binary from an Aura checkout, then run the smoke test:

```sh
./scripts/smoke.sh /tmp/aura-registry-proxy
```

The smoke test verifies health, metadata, a chunked upstream response, a
binary archive round trip, lazy cache materialization, a missing object, and
cache hits after the upstream is stopped.

