#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

#
# Flatten a runner OCI image into a single ext4 filesystem image — the Firecracker guest rootfs.
# `docker export` of a created (never started) container gives exactly the image's filesystem,
# which is tar-extracted into a fresh loop-mounted ext4. At runtime the platform mounts this
# READ-ONLY with a per-VM writable overlay; this recipe just produces the base filesystem.
#
# Usage: guest/rootfs/oci_to_ext4.sh <image-ref> <out.ext4> [size-mb]
#   size-mb defaults to the image's reported size plus ~40% + 256 MiB headroom (ext4 metadata,
#   runtime scratch before the overlay mounts, and room for growth between pin bumps).
#
# Needs: x86_64 Linux, docker, sudo (loop mount). Pulls --platform linux/amd64 — guests are x86_64.

set -euo pipefail

IMAGE="${1:?usage: oci_to_ext4.sh <image-ref> <out.ext4> [size-mb]}"
OUT="${2:?usage: oci_to_ext4.sh <image-ref> <out.ext4> [size-mb]}"
SIZE_MB="${3:-}"

[ "$(uname -sm)" = "Linux x86_64" ] || { echo "oci_to_ext4: needs x86_64 Linux" >&2; exit 1; }
command -v docker >/dev/null || { echo "oci_to_ext4: docker is required" >&2; exit 1; }

echo "== pulling $IMAGE (linux/amd64) =="
docker pull --platform linux/amd64 "$IMAGE"

if [ -z "$SIZE_MB" ]; then
  bytes="$(docker image inspect -f '{{.Size}}' "$IMAGE")"
  SIZE_MB=$(((bytes / 1024 / 1024) * 14 / 10 + 256))
fi
echo "== creating ${SIZE_MB} MiB ext4 =="
rm -f "$OUT"
truncate -s "${SIZE_MB}M" "$OUT"
mkfs.ext4 -q -F -L bwroot "$OUT"

CID="$(docker create --platform linux/amd64 "$IMAGE" /bin/true)"
MNT="$(mktemp -d)"
cleanup() {
  sudo umount "$MNT" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
  docker rm -f "$CID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sudo mount -o loop "$OUT" "$MNT"
echo "== exporting image filesystem =="
docker export "$CID" | sudo tar -x -C "$MNT" --numeric-owner
# Mount points the guest init expects to exist on the read-only base.
sudo mkdir -p "$MNT/proc" "$MNT/sys" "$MNT/dev" "$MNT/workspace"
sudo umount "$MNT"

echo "OK $OUT ($(du -h "$OUT" | cut -f1) apparent, label bwroot)"
