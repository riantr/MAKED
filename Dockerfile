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
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gcc \
      git \
      make \
 && rm -rf /var/lib/apt/lists/*

# The same installer URL the CI workflow uses, verified on a runner.
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:${PATH}"

WORKDIR /app
COPY . .

# `moon update` refreshes the registry index and the lockfile but does not
# download the packages; `moon install` is what populates `.mooncakes/`.
# Without the second command the build fails with
# ".mooncakes/riantr/pyroduct/src is missing".
RUN moon update && moon install

# The browser bundle and the server. The bundle is copied to where the server
# looks for it, because `moon build --target js` names the output file itself
# and the server expects `frontend/dist/main.js`.
RUN moon build --release --target js cmd/web \
 && cp _build/js/release/build/cmd/web/web.js frontend/dist/main.js \
 && moon build --release --target native cmd/server

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

COPY --from=build /app/_build/native/release/build/cmd/server/server /usr/local/bin/maked
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
