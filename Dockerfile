# MAKED in a container.
#
# The point of this file is the first barrier a newcomer hits: the MoonBit
# toolchain, a native C toolchain, and a build step. Someone who only wants
# to *look at* MAKED should not have to install any of it.
#
#   docker run --rm -p 8080:8080 ghcr.io/riantr/maked:latest
#
# Two stages, and the runtime stage contains no compiler, no toolchain and no
# source. The build stage and the runtime stage are the SAME base image on
# purpose: a binary built against a newer glibc than the runtime image has
# fails at startup with a version error that reads like a corrupt download.
#
# The database lives in /data, which is a volume, so records survive a
# container being replaced. The server creates and seeds it on first run.

# syntax=docker/dockerfile:1

# ---------------------------------------------------------------- build ----
FROM debian:bookworm-slim AS build

# `gcc` and `make` are not optional. The sqlite3 dependency is the SQLite
# amalgamation (a 9 MB C file) that the native build compiles and links in,
# so there is no system sqlite to install and no shared library to ship.
#
# `libc6-dev` is not optional either, and its absence is quiet: without it the
# build dies with "stdint.h: No such file or directory", because gcc ships the
# compiler while the headers for the C standard library live in a separate
# package. `--no-install-recommends` is what keeps it out.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gcc \
      git \
      libc6-dev \
      make \
 && rm -rf /var/lib/apt/lists/*

# The same installer URL the CI workflow uses, verified on a runner.
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:${PATH}"

WORKDIR /app
COPY . .

# `moon update` refreshes the registry index and the lockfile. The packages
# themselves are downloaded by the build below: since 0.1.20261016 the
# toolchain resolves the dependency tree during `moon build` itself, and the
# old `moon install` (without a source) is now a hard error -- "the following
# required arguments were not provided: <SOURCE>".
RUN moon update

# The browser bundle and the server. The bundle is copied to where the server
# looks for it, because `moon build --target js` names the output file itself
# and the server expects `frontend/dist/main.js`.
#
# Both outputs are found with `find` rather than written as a fixed path. The
# path inside `_build/` is moon's business, not ours, and it is not the same
# on every platform: a hard-coded path is a build that breaks when moon moves
# a directory, and it breaks on the platform nobody tested.
RUN moon build --release --target js cmd/web \
 && cp "$(find _build/js -type f -name 'web.js' | head -1)" frontend/dist/main.js \
 && moon build --release --target native cmd/server \
 && mkdir -p /out \
 && cp "$(find _build/native -type f \( -name 'server' -o -name 'server.exe' \) | head -1)" /out/maked

# -------------------------------------------------------------- runtime ----
FROM debian:bookworm-slim AS runtime

# curl is here for the health check below, and because it is the first thing
# anyone wants inside a container that is not answering.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /home/maked --shell /usr/sbin/nologin maked \
 && mkdir -p /data \
 && chown maked:maked /data

COPY --from=build /out/maked /usr/local/bin/maked
COPY --from=build /app/frontend/dist /opt/maked/frontend/dist

# The server takes its port, its database and its static files from the
# environment, and this is what sets the defaults for the container.
ENV MAKED_PORT=8080 \
    MAKED_DB=/data/maked.db \
    MAKED_DIST=/opt/maked/frontend/dist

WORKDIR /data
VOLUME ["/data"]
EXPOSE 8080
USER maked

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${MAKED_PORT}/api/status" || exit 1

ENTRYPOINT ["/usr/local/bin/maked"]
