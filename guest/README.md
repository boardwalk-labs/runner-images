# Firecracker guest artifacts

Recipes for the artifacts a Boardwalk hosted runner needs when it executes inside a
**Firecracker microVM** instead of a container: a guest **kernel** and an **ext4 rootfs**
flattened from a runner OCI image. Same trust story as the container images ([SPEC](../SPEC.md)):
what your code runs inside is defined here, pinned, and rebuildable by anyone. (Rebuildable, not
bit-reproducible: the KBUILD identity stamps are pinned but the host toolchain is not, so two
builders can get different hashes of a byte-equivalent-in-behavior kernel. Once publishing is
wired up — see [Publishing](#publishing) — the CI build is the canonical artifact; until then
the `.sha256` + archived `.config` emitted beside each hand-built artifact are the record of
what was built.)

Firecracker boots a kernel directly (no bootloader, no disk image with a boot partition), so the
guest is exactly these two files plus an init process:

| Artifact | Recipe | What it is |
| --- | --- | --- |
| `vmlinux-<version>` | [`kernel/build_kernel.sh`](./kernel/build_kernel.sh) | Minimal uncompressed x86_64 kernel, built from kernel.org sources with Firecracker's CI microvm config, verified against [`kernel/required.config`](./kernel/required.config) |
| `rootfs.ext4` | [`rootfs/oci_to_ext4.sh`](./rootfs/oci_to_ext4.sh) | Any runner OCI image (e.g. `boardwalk-runner-linux`) flattened to a single ext4 filesystem |

The guest **init** (PID 1) is not defined here — it is part of the platform's private runtime
layer, exactly like the worker runtime layered onto the container base images. These recipes are
the public substrate under it.

## Kernel

```sh
guest/kernel/build_kernel.sh          # → guest/kernel/dist/vmlinux-<version> (+ .sha256 + .config)
```

Pins (override via env):

- `KERNEL_VERSION` + `KERNEL_SHA256` — a kernel.org 6.1.x LTS release and the sha256 of its
  tarball (from kernel.org's signed `sha256sums.asc`). The source download is
  integrity-verified before anything is built; bumping the version means bumping both.
- `FC_COMMIT` (with `FC_TAG` as the human-readable name) — the Firecracker release whose CI guest
  config is used as the base config
  (`resources/guest_configs/microvm-kernel-ci-x86_64-6.1.config`), pinned to the commit the tag
  pointed to when it was vetted — tags can be force-moved, commits cannot. Using Firecracker's
  own CI config means the device set matches what Firecracker actually emulates and tests against.

After `make olddefconfig`, the build **fails unless every option in
[`required.config`](./kernel/required.config) is set** — the options the runner substrate depends
on (virtio net/blk/vsock/rng, ext4, ACPI + VMGenID for snapshot-restore reseeding, overlayfs +
tmpfs, devtmpfs device nodes, the ttyS0 serial console, sysrq, kvmclock). That assert is the
contract: bumping either pin cannot silently drop a required capability. The exact resolved
config that produced a kernel is archived beside it as `vmlinux-<version>.config`.

Build host requirements: x86_64 Linux, the usual kernel build deps (`gcc make flex bison bc
elfutils-libelf-devel openssl-devel perl` on Fedora/AL2023; the script checks and names anything
missing). Takes a few minutes on 8 vCPUs.

## Rootfs

```sh
guest/rootfs/oci_to_ext4.sh ghcr.io/boardwalk-labs/boardwalk-runner-linux@sha256:<digest> rootfs.ext4
```

Flattens the image's filesystem (`docker export`) into a fresh ext4 file, auto-sized from the
image with headroom (override with a third `size-mb` argument). Runs on x86_64 Linux
(needs `docker` and `sudo` for the loop mount). The image is pulled `--platform linux/amd64`:
Firecracker guests here are x86_64.

The rootfs is only as pinned as its input, so canonical builds take the image **by digest**
(`@sha256:...` — a tag can move, a digest cannot); the script warns on a tag-only ref. A plain
`:<version>` tag is fine for local iteration.

At runtime the platform mounts the rootfs **read-only with a per-VM writable overlay** (that is
why `required.config` demands overlayfs); the recipe itself just produces the base filesystem.

## Smoke boot

```sh
guest/smoke_boot.sh guest/kernel/dist/vmlinux-<version> rootfs.ext4
```

Boots the pair in a throwaway microVM (needs `firecracker` on `$PATH`, `/dev/kvm`, and a rootfs
with a POSIX `/bin/sh`), with a temporary init injected into a scratch copy of the rootfs. Passes
when the guest reaches userspace on the ext4 root, enumerates its virtio devices (root disk +
vsock), finds `/dev/vsock`, offers overlayfs + tmpfs (the production read-only-base + writable-
overlay mount shape), and can power itself off (a guest that wedges at shutdown fails). Set
`SMOKE_SCRATCH_DIR` if `/tmp` is a tmpfs — the scratch rootfs copy is full-size. This is the
recipe-level gate; deeper checks (vsock round-trips, snapshot/restore, VMGenID reseed
observation) belong to the platform's runtime tests, not the image recipes.

## Publishing

Not yet wired into CI. The plan mirrors the container images: canonical artifacts build in this
repo's CI on x86_64 and publish versioned + checksummed alongside image releases, and the
platform consumes them by digest. Until then, build from source with the recipes above.
