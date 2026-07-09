# `boardwalk/linux-desktop`

`boardwalk/linux` plus an on-screen desktop and a browser tier. Image:
`ghcr.io/boardwalk-labs/boardwalk-runner-linux-desktop:<version>` (always referenced by digest in
production). It **derives from `boardwalk/linux` by digest**, so everything in that image is present
here too; this page covers only what it adds.

This is the image the hosted platform runs so that every hosted run has a screen (the ambient-desktop
model — a run does not opt into a desktop, it has one) and browser-session computer use
(`computer.openBrowser()` in the SDK) works out of the box. Chromium is the largest CVE surface in
the stack, which is exactly why it lives in this **separate, public, SBOM'd + scanned** image rather
than in the minimal base (a plain run that never opens a browser should not carry it) or in a private
layer (the widest injection surface is better audited in the open).

## Installed tools (in addition to `boardwalk/linux`)

| Tool | Source | Version policy |
| --- | --- | --- |
| Xvfb (headless X server) | Debian bookworm `xvfb` | follows parent digest; locked in `ENVIRONMENT.lock` |
| Openbox (window manager) | Debian bookworm `openbox` | follows parent digest; locked |
| Chromium | Debian bookworm `chromium` (+ `chromium-common`, `chromium-sandbox`) | follows parent digest; locked |
| Playwright MCP | npm global, pinned `ARG PLAYWRIGHT_MCP_VERSION` | explicit bump |
| x11-utils, xauth | Debian bookworm packages | follows parent digest; locked |
| fonts-liberation, fonts-noto-core, fonts-noto-color-emoji | Debian bookworm packages | follows parent digest; locked |

## Helper binaries

- **`boardwalk-start-desktop`** — brings up the desktop: starts Xvfb on `$DISPLAY` (default `:0`,
  geometry `BOARDWALK_DESKTOP_SCREEN`, default `1280x800x24`), waits for X to answer, then starts the
  window manager. The platform's worker/guest-init calls this so the desktop is up in the base
  snapshot.
- **`boardwalk-chromium`** — a thin Chromium launcher with the flags a containerized/microVM Chromium
  needs (`--no-sandbox` — the VM is the sandbox; `--disable-dev-shm-usage`; `--disable-gpu`). The
  platform runner points its browser session at this and appends `--remote-debugging-port`,
  `--user-data-dir`, and the start URL.

## Browser-tier contract

The image sets the environment the Boardwalk runner reads to enable and drive the browser tier:

| Variable | Value | Meaning |
| --- | --- | --- |
| `BOARDWALK_BROWSER_TIER` | `1` | The runner constructs a per-run browser-session manager. |
| `BOARDWALK_BROWSER_CHROME_PATH` | `/usr/local/bin/boardwalk-chromium` | The program-owned CDP Chromium. |
| `BOARDWALK_BROWSER_MCP_COMMAND` | `playwright-mcp` | Run the pinned, pre-installed Playwright MCP directly (no runtime download). |
| `DISPLAY` | `:0` | The screen Chromium renders on (headful, so the capture tier can mirror it). |

A browser session is a program-owned Chromium exposing a CDP endpoint, with a per-session Playwright
MCP HTTP server attached to it; the agent drives the browser through that MCP server. Everything runs
on the loopback interface inside the run's sandbox.

## Filesystem, user, network, resource limits

Same as [`boardwalk/linux`](./linux.md): runs as the unprivileged `node` user, `/workspace` is the
writable working dir + `HOME`, and the image imposes no network policy of its own (egress is a
property of where the runner executes). Chromium and Playwright MCP run as `node`.

## Compatibility notes

- Published for **`linux/amd64` and `linux/arm64`** (multi-arch index, like the base).
- Chromium is launched via the `boardwalk-chromium` wrapper, not `/usr/bin/chromium` directly — the
  wrapper carries the sandbox/shm/gpu flags the isolated environment needs.
- The desktop is headless (Xvfb): there is no physical display; the screen exists to be captured and
  for the browser to render into.
- `ENVIRONMENT.lock` is regenerated on `linux/amd64` in CI and must match the built image — a package
  change (including a Chromium security bump inherited from the parent digest) lands as a reviewed
  diff.
