#!/bin/bash

## ------------------
## Dependencies magic
## ------------------

set -ex

# should exist when $DEMO=TRUE to avoid 'COPY --from=dependencies-builder /builddeps/wal-g ...' failure

if [ "$DEMO" = "true" ]; then
    mkdir /builddeps/wal-g
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive
MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)"
export MAKEFLAGS
ARCH="$(dpkg --print-architecture)"

# We want to remove all libgdal30 debs except one that is for current architecture.
printf "shopt -s extglob\nrm /builddeps/!(*_%s.deb)" "$ARCH" | bash -s

echo -e 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend

apt-get update
apt-get install -y curl ca-certificates

mkdir /builddeps/wal-g

# build wal-g from a pinned source commit instead of the prebuilt release.
# Released wal-g binaries (<= v3.0.8) ship stale Go deps with critical CVEs
# (x/crypto, grpc, Go stdlib); building from current source clears them.
# `make deps` must stay serial (no -j) or the brotli/cmake step races and fails.
GO_VERSION=1.25.11
apt-get install -y --no-install-recommends git build-essential cmake liblzo2-dev
curl -sL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
export PATH="/usr/local/go/bin:$PATH"

git clone https://github.com/wal-g/wal-g.git /tmp/wal-g
cd /tmp/wal-g
git checkout "$WALG_REF"
git submodule update --init --recursive
# MAKEFLAGS is exported with -j above; clear it here so the brotli/cmake step
# in `make deps` builds serially (parallel build races and fails under emulation).
MAKEFLAGS= USE_BROTLI=1 make deps
MAKEFLAGS= USE_BROTLI=1 make pg_build
cp main/pg/wal-g /builddeps/wal-g/wal-g
cd /
