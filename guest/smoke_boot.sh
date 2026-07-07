#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

#
# Smoke-boot a kernel + rootfs pair in a throwaway Firecracker microVM: the recipe-level gate
# that the two artifacts actually make a bootable guest. A temporary init is injected into a
# SCRATCH COPY of the rootfs (the input file is never modified); the guest passes when it
# reaches userspace on the ext4 root, enumerates its virtio devices (root disk + vsock), and
# finds /dev/vsock. Deeper checks (vsock round-trips, snapshot/restore, VMGenID reseed) are
# platform runtime tests, not image-recipe gates.
#
# Usage: guest/smoke_boot.sh <vmlinux> <rootfs.ext4>
# Needs: firecracker on $PATH, /dev/kvm, sudo (loop mount for the init injection).

set -euo pipefail

VMLINUX="${1:?usage: smoke_boot.sh <vmlinux> <rootfs.ext4>}"
ROOTFS="${2:?usage: smoke_boot.sh <vmlinux> <rootfs.ext4>}"
TIMEOUT_S="${SMOKE_TIMEOUT_S:-90}"

command -v firecracker >/dev/null || { echo "smoke_boot: firecracker not on PATH" >&2; exit 1; }
[ -r /dev/kvm ] && [ -w /dev/kvm ] || { echo "smoke_boot: /dev/kvm not accessible" >&2; exit 1; }

SCRATCH="$(mktemp -d)"
cleanup() {
  sudo umount "$SCRATCH/mnt" 2>/dev/null || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

cp --sparse=always "$ROOTFS" "$SCRATCH/rootfs.ext4"

# The throwaway init: prove userspace + a writable root + the virtio device set, print a
# verdict marker on the serial console, then reboot -f (which exits the Firecracker VMM).
cat >"$SCRATCH/bwsmoke" <<'EOF'
#!/bin/bash
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
echo "bwsmoke: kernel $(uname -r)"
fail=0
virtio_count=$(ls /sys/bus/virtio/devices 2>/dev/null | wc -l)
echo "bwsmoke: virtio devices: ${virtio_count} ($(ls /sys/bus/virtio/devices 2>/dev/null | tr '\n' ' '))"
[ "${virtio_count}" -ge 2 ] || { echo "bwsmoke: FAIL expected >=2 virtio devices (root blk + vsock)"; fail=1; }
[ -e /dev/vsock ] && echo "bwsmoke: /dev/vsock present" || { echo "bwsmoke: FAIL /dev/vsock missing"; fail=1; }
touch /bwsmoke-write-test 2>/dev/null && echo "bwsmoke: root is writable" || { echo "bwsmoke: FAIL root not writable"; fail=1; }
[ "${fail}" -eq 0 ] && echo "GUEST_SMOKE_OK" || echo "GUEST_SMOKE_FAIL"
# Exit the VMM without relying on image binaries (a container-oriented rootfs has no `reboot`):
# sysrq poweroff if the kernel allows it; else PID 1 exits, and panic=-1 reboots, which also
# exits Firecracker. The verdict marker above already printed either way.
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo o > /proc/sysrq-trigger 2>/dev/null
exit 0
EOF

mkdir -p "$SCRATCH/mnt"
sudo mount -o loop "$SCRATCH/rootfs.ext4" "$SCRATCH/mnt"
sudo install -m 0755 "$SCRATCH/bwsmoke" "$SCRATCH/mnt/sbin/bwsmoke"
sudo umount "$SCRATCH/mnt"

cat >"$SCRATCH/vm.json" <<EOF
{
  "boot-source": {
    "kernel_image_path": "$VMLINUX",
    "boot_args": "console=ttyS0 reboot=k panic=-1 pci=off root=/dev/vda rw init=/sbin/bwsmoke"
  },
  "drives": [
    { "drive_id": "rootfs", "path_on_host": "$SCRATCH/rootfs.ext4", "is_root_device": true, "is_read_only": false }
  ],
  "machine-config": { "vcpu_count": 2, "mem_size_mib": 1024 },
  "vsock": { "guest_cid": 3, "uds_path": "$SCRATCH/v.sock" }
}
EOF

echo "== booting (timeout ${TIMEOUT_S}s) =="
set +e
timeout "$TIMEOUT_S" firecracker --no-api --config-file "$SCRATCH/vm.json" >"$SCRATCH/console.log" 2>&1
set -e

if grep -q "GUEST_SMOKE_OK" "$SCRATCH/console.log"; then
  grep "bwsmoke:" "$SCRATCH/console.log"
  echo "PASS"
else
  echo "smoke_boot: FAILED — console tail:" >&2
  tail -40 "$SCRATCH/console.log" >&2
  exit 1
fi
