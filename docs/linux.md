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
| Chromium (+ `boardwalk-chromium` wrapper) | Debian bookworm package | follows parent digest |
| Playwright MCP server (`playwright-mcp`) | npm, pinned `ARG PLAYWRIGHT_MCP_VERSION` | explicit bump |
| Xvfb, openbox, ffmpeg, feh, tint2, sakura | Debian bookworm packages | follows parent digest |

Anything not listed is not present. Workflows needing more either install it inside the run
(subject to the run's egress policy) or use a custom runner image.

## Desktop tier — one image, no variants

Every runner image ships the desktop/browser capability; there is no separate headless variant.
Certain platform behaviors are enabled by default, so the display stack is part of what a
Boardwalk runner *is* — and a single image per OS (the GitHub-Actions model) keeps
the trust surface, the version pin, and the environment lock singular.

- **Display:** Xvfb (virtual framebuffer) + openbox, brought up by
  `/usr/local/bin/boardwalk-start-desktop` when the platform layer enables it. The image sets
  `DISPLAY=:0`.
- **Browser:** Debian Chromium via the `/usr/local/bin/boardwalk-chromium` wrapper
  (`--no-sandbox --disable-dev-shm-usage --disable-gpu` — the runner boundary is the sandbox).
- **Automation:** the Playwright MCP server (`playwright-mcp`) drives the same Chromium.
- **Recording:** ffmpeg captures the session; feh/tint2/sakura render the ambient desktop
  (wallpaper, dock, live run-output terminal).
- **Contract env** (baked into the image, consumed by the layers above it):
  `BOARDWALK_BROWSER_TIER=1`, `BOARDWALK_BROWSER_CHROME_PATH`, `BOARDWALK_BROWSER_MCP_COMMAND`,
  `BOARDWALK_RUN_LOG_FILE`, `DISPLAY`.

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
`runs_on` size) and are enforced by the platform running the container. A larger machine is the
`runs_on` `size` selector on this same image: a per-run resource override, not a separate image.

## Compatibility notes

- Published for **`linux/amd64` and `linux/arm64`** — the release tag/digest is a multi-arch index,
  so a pull (or a `FROM` by digest) resolves to your platform's variant.
- Debian bookworm / glibc — binaries built for musl (Alpine) may not run.
- `python` (unversioned) is not aliased; use `python3`.
- Node global installs land in the image's npm prefix and are not writable at run time; install
  per-run dependencies into `/workspace`.
