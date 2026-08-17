# syntax=docker/dockerfile:1

FROM ubuntu:24.04 AS builder

ARG AURA_VERSION=0.1.1-alpha.8
ENV AURA_HOME=/opt/aura
ENV PATH="${AURA_HOME}/bin:${PATH}"
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libssl-dev \
        pkg-config \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Aura 0.1.1-alpha.8 emits strdup without a feature macro and builds with
# development sanitizers that are not needed in the runtime image.
RUN printf '%s\n' \
        '#!/bin/bash' \
        'args=()' \
        'for arg in "$@"; do' \
        '    [[ "$arg" == "-fsanitize=address,undefined" ]] || args+=("$arg")' \
        'done' \
        'exec cc -D_POSIX_C_SOURCE=200809L "${args[@]}"' \
        > /usr/local/bin/aura-cc \
    && chmod +x /usr/local/bin/aura-cc

ENV CC=/usr/local/bin/aura-cc

RUN curl --fail --silent --show-error --location \
        https://aura.pilotworks.dev/install.sh \
        | AURA_VERSION="${AURA_VERSION}" \
          AURA_HOME="${AURA_HOME}" \
          AURA_LINK_USER_BIN=0 \
          AURA_NO_PATH_HINT=1 \
          bash

WORKDIR /src
COPY aura.toml main.aura ./

RUN mkdir -p /out \
    && aura build . -o /out/registry-proxy-aura --rebuild-runtime


FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        libssl3 \
        socat \
        zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system aura \
    && useradd --system --gid aura --home-dir /app --shell /usr/sbin/nologin aura \
    && mkdir -p /data/registry \
    && chown aura:aura /data/registry

COPY --from=builder /out/registry-proxy-aura /usr/local/bin/registry-proxy-aura

ENV AURA_REGISTRY_ROOT=/data/registry

USER aura
EXPOSE 8080
VOLUME ["/data/registry"]

ENTRYPOINT ["sh", "-c", "port=${1:-8080}; socat TCP-LISTEN:${port},fork,reuseaddr TCP:127.0.0.1:18080 & exec /usr/local/bin/registry-proxy-aura 18080", "--"]
CMD ["8080"]
