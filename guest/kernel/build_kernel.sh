#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

#
# Build the Boardwalk Firecracker guest kernel: an uncompressed x86_64 `vmlinux` from pinned
# kernel.org sources, configured with the pinned Firecracker release's own CI microvm config
# (so the device set matches what Firecracker emulates and tests), then verified against
# required.config — the build FAILS if a required capability is missing, which is the guard
# that a pin bump can't silently drop something the runner substrate depends on.
#
# Usage: guest/kernel/build_kernel.sh          # → guest/kernel/dist/vmlinux-<version> (+ .sha256)
# Pins:  KERNEL_VERSION (kernel.org 6.1.x LTS), FC_TAG (Firecracker release for the base config)

set -euo pipefail

KERNEL_VERSION="${KERNEL_VERSION:-6.1.155}"
FC_TAG="${FC_TAG:-v1.16.0}"

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
  tar -C "$BUILD" -xf "$BUILD/linux-$KERNEL_VERSION.tar.xz"
fi

echo "== base config: Firecracker $FC_TAG CI microvm config =="
curl -fsSL -o "$SRC/.config" \
  "https://raw.githubusercontent.com/firecracker-microvm/firecracker/$FC_TAG/resources/guest_configs/microvm-kernel-ci-x86_64-6.1.config"
make -C "$SRC" olddefconfig

echo "== verifying required options =="
absent=()
while IFS= read -r line; do
  case "$line" in ""|"#"*) continue ;; esac
  grep -qx "$line" "$SRC/.config" || absent+=("$line")
done <"$REQUIRED"
if [ "${#absent[@]}" -gt 0 ]; then
  printf 'build_kernel: required option(s) missing from the resolved .config:\n' >&2
  printf '  %s\n' "${absent[@]}" >&2
  echo "The FC_TAG/KERNEL_VERSION pin combination dropped a required capability — do not ship this config." >&2
  exit 1
fi

echo "== building vmlinux (-j$(nproc)) =="
make -C "$SRC" -j"$(nproc)" vmlinux

OUT="$DIST/vmlinux-$KERNEL_VERSION"
cp "$SRC/vmlinux" "$OUT"
(cd "$DIST" && sha256sum "vmlinux-$KERNEL_VERSION" | tee "vmlinux-$KERNEL_VERSION.sha256")
echo "OK $OUT"
