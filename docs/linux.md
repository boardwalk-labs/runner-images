# `boardwalk/linux`

The default hosted-runner environment. Image: `ghcr.io/boardwalk-labs/boardwalk-runner-linux:<version>` (always referenced by digest in production).

## Installed tools

| Tool | Source | Version policy |
| --- | --- | --- |
| Node.js 24 (LTS) + npm | parent image `node:24-bookworm-slim` (pinned by digest) | parent digest bump = reviewed PR |
| pnpm | npm global install, pinned `ARG PNPM_VERSION` (NOT corepack — it lazy-downloads at run time) | explicit bump |
| tsx | npm, pinned `ARG TSX_VERSION` | explicit bump |
| git, curl, jq, tar, unzip, xz | Debian bookworm packages | follows parent digest |
| python3 (3.11), pip, venv | Debian bookworm packages | follows parent digest |
| gh (GitHub CLI) | pinned release `.deb`, `ARG GH_VERSION` | explicit bump |
| openssh-client | Debian bookworm package | follows parent digest |
| bash, coreutils | Debian bookworm | follows parent digest |

Anything not listed is not present. Workflows needing more either install it inside the run
(subject to the run's egress policy) or use a custom runner image.

## Filesystem layout

- **`/workspace`** — the run's working directory, `HOME`, and cwd. Writable by the default user.
  Whether its contents survive across runs is the *workflow's* choice (`workspace.persist` in the
  manifest); the engine layer above this image owns hydration/persistence. Everything else in the
  image should be treated as read-only.
- **`/tmp`** — ephemeral scratch, cleared per run.

## User and permissions

Runs execute as the unprivileged `node` user (uid/gid 1000). No sudo. Derived images may use
root for their own build layer but must end on a non-root user.

## Network

The image itself imposes no network policy — egress control is a property of where the runner
executes (hosted Boardwalk applies the workflow's declared egress policy to hosted runs;
self-hosted runners inherit your network). TLS roots come from `ca-certificates`.

## Resource limits

CPU/memory/timeout are not baked into the image; they come from the run's manifest (`budget`,
`runs_on` size) and are enforced by the platform running the container.

## Compatibility notes

- Published for **`linux/amd64` and `linux/arm64`** — the release tag/digest is a multi-arch index,
  so a pull (or a `FROM` by digest) resolves to your platform's variant.
- Debian bookworm / glibc — binaries built for musl (Alpine) may not run.
- `python` (unversioned) is not aliased; use `python3`.
- Node global installs land in the image's npm prefix and are not writable at run time; install
  per-run dependencies into `/workspace`.
