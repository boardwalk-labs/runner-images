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

# The rootfs is only as pinned as its input: a tag can move between builds, a digest cannot.
# Warn (not fail — local iteration on a just-built tag is legitimate) so a canonical build
# without @sha256 is a conscious choice, never an accident.
case "$IMAGE" in
*@sha256:*) ;;
*) echo "oci_to_ext4: WARNING: image ref is not digest-pinned (@sha256:...) — the output is only as reproducible as this tag" >&2 ;;
esac

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

# Install the trap before creating anything it cleans up, so a failure between the two
# steps (e.g. mktemp) can't leak the container.
CID=""
MNT=""
cleanup() {
  if [ -n "$MNT" ]; then
    sudo umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
  fi
  if [ -n "$CID" ]; then
    docker rm -f "$CID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
CID="$(docker create --platform linux/amd64 "$IMAGE" /bin/true)"
MNT="$(mktemp -d)"

sudo mount -o loop "$OUT" "$MNT"
echo "== exporting image filesystem =="
# --xattrs: preserve extended attributes (file capabilities, security labels) — a setcap'd
# binary that works in the container lane must not silently lose its caps in the microVM lane.
docker export "$CID" | sudo tar -x -C "$MNT" --numeric-owner --xattrs --xattrs-include='*'
# Mount points the guest init expects to exist on the read-only base.
sudo mkdir -p "$MNT/proc" "$MNT/sys" "$MNT/dev" "$MNT/workspace"

# `docker export` omits Config.Env, so persist only the image's public browser contract. Parse the
# inspect output as JSON and shell-quote each value before guest startup reads the assignment file.
# A restrictive mode limits the file to the root-owned startup process.
command -v python3 >/dev/null || { echo "oci_to_ext4: python3 is required" >&2; exit 1; }
docker image inspect -f '{{json .Config.Env}}' "$IMAGE" \
  | python3 -c '
import json
import shlex
import sys

allowed = {
    "BOARDWALK_BROWSER_TIER",
    "BOARDWALK_BROWSER_CHROME_PATH",
    "BOARDWALK_BROWSER_MCP_COMMAND",
    "DISPLAY",
}
for item in json.load(sys.stdin) or []:
    key, separator, value = item.partition("=")
    if separator and key in allowed:
        print(f"{key}={shlex.quote(value)}")
' \
  | sudo install -m 0600 /dev/stdin "$MNT/etc/bwimage.env"

sudo umount "$MNT"

echo "OK $OUT ($(du -h "$OUT" | cut -f1) apparent, label bwroot)"
