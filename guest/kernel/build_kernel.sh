#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

#
# Build the Boardwalk Firecracker guest kernel: an uncompressed x86_64 `vmlinux` from pinned
# kernel.org sources, configured with the pinned Firecracker release's own CI microvm config
# (so the device set matches what Firecracker emulates and tests), then verified against
# required.config — the build FAILS if a required capability is missing, which is the guard
# that a pin bump can't silently drop something the runner substrate depends on.
#
# Usage: guest/kernel/build_kernel.sh          # → guest/kernel/dist/vmlinux-<version> (+ .sha256 + .config)
# Pins:  KERNEL_VERSION + KERNEL_SHA256 (kernel.org 6.1.x LTS — override BOTH together),
#        FC_COMMIT (Firecracker release for the base config, pinned to the commit the tag
#        pointed to when vetted — a tag can be force-moved, a commit SHA cannot)

set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:-6.1.155}"
# sha256 of linux-$KERNEL_VERSION.tar.xz, from kernel.org's signed sha256sums.asc. The kernel is
# the single most security-critical artifact this repo produces — TLS alone is not an integrity
# story for it. Overriding KERNEL_VERSION requires overriding this in the same breath.
KERNEL_SHA256="${KERNEL_SHA256:-c29387aeee085fbcbd91236224b9df805063bac43615e75cea2c6b29604a5c73}"
FC_TAG="${FC_TAG:-v1.16.0}"                                        # for humans + logs
FC_COMMIT="${FC_COMMIT:-d83d72b710361a10294480131377b1b00b163af8}" # v1.16.0 at vetting time

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build"
DIST="$HERE/dist"
REQUIRED="$HERE/required.config"

[ "$(uname -sm)" = "Linux x86_64" ] || {
  echo "build_kernel: needs an x86_64 Linux build host (guests are x86_64-only)" >&2
  exit 1
}

missing=()
for tool in gcc make flex bison bc perl; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "build_kernel: missing build tools: ${missing[*]}" >&2
  echo "  Fedora/AL2023: sudo dnf install -y gcc make flex bison bc elfutils-libelf-devel openssl-devel perl" >&2
  echo "  Debian/Ubuntu: sudo apt-get install -y build-essential flex bison bc libelf-dev libssl-dev" >&2
  exit 1
fi

mkdir -p "$BUILD" "$DIST"
SRC="$BUILD/linux-$KERNEL_VERSION"

if [ ! -d "$SRC" ]; then
  echo "== fetching linux-$KERNEL_VERSION =="
  curl -fsSL -o "$BUILD/linux-$KERNEL_VERSION.tar.xz" \
    "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz"
  (cd "$BUILD" && echo "$KERNEL_SHA256  linux-$KERNEL_VERSION.tar.xz" | sha256sum -c -) || {
    echo "build_kernel: linux-$KERNEL_VERSION.tar.xz failed sha256 verification — refusing to build." >&2
    echo "If you bumped KERNEL_VERSION, set KERNEL_SHA256 from kernel.org's sha256sums.asc too." >&2
    rm -f "$BUILD/linux-$KERNEL_VERSION.tar.xz"
    exit 1
  }
  tar -C "$BUILD" -xf "$BUILD/linux-$KERNEL_VERSION.tar.xz"
fi

echo "== base config: Firecracker $FC_TAG CI microvm config (commit $FC_COMMIT) =="
curl -fsSL -o "$SRC/.config" \
  "https://raw.githubusercontent.com/firecracker-microvm/firecracker/$FC_COMMIT/resources/guest_configs/microvm-kernel-ci-x86_64-6.1.config"
make -C "$SRC" olddefconfig

echo "== verifying required options =="
absent=()
while IFS= read -r line; do
  case "$line" in ""|"#"*) continue ;; esac
  grep -qxF "$line" "$SRC/.config" || absent+=("$line")
done <"$REQUIRED"
if [ "${#absent[@]}" -gt 0 ]; then
  printf 'build_kernel: required option(s) missing from the resolved .config:\n' >&2
  printf '  %s\n' "${absent[@]}" >&2
  echo "The FC_TAG/KERNEL_VERSION pin combination dropped a required capability — do not ship this config." >&2
  exit 1
fi

echo "== building vmlinux (-j$(nproc)) =="
# Pin the KBUILD identity stamps so rebuilds don't differ just by who/when/where. The host
# toolchain (gcc) is still unpinned, so this is auditable-rebuildable, not bit-reproducible;
# the CI build becomes the canonical artifact once publishing is wired up (README
# "Publishing") — until then the .sha256 + archived .config beside each build are the record.
make -C "$SRC" -j"$(nproc)" \
  KBUILD_BUILD_TIMESTAMP="linux-$KERNEL_VERSION" \
  KBUILD_BUILD_USER=boardwalk KBUILD_BUILD_HOST=runner-images \
  vmlinux

OUT="$DIST/vmlinux-$KERNEL_VERSION"
cp "$SRC/vmlinux" "$OUT"
# Archive the resolved config beside the kernel: given a published vmlinux there must be an
# exact record of the config that produced it (the base config URL alone can't promise that).
cp "$SRC/.config" "$OUT.config"
(cd "$DIST" && sha256sum "vmlinux-$KERNEL_VERSION" | tee "vmlinux-$KERNEL_VERSION.sha256")
echo "OK $OUT"
