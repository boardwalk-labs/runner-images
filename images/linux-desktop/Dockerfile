# SPDX-License-Identifier: Apache-2.0

# boardwalk/linux-desktop — the base image plus an on-screen desktop and a browser tier.
#
# Derives from boardwalk/linux by digest and adds exactly the COMMODITY, publicly-auditable half of
# the computer-use runtime: an X display (Xvfb + a window manager), Chromium, and a pinned Playwright
# MCP. This is the image the hosted fleet runs so that every hosted run has a screen (the
# ambient-desktop model — a run does not opt into a desktop, it has one) and `computer.openBrowser()`
# just works. The platform's PRIVATE worker layer adds only the broker-coupled capture / live-view
# agent on top of this; self-hosters who want the browser tier can use this image directly.
#
# Why a separate public image and not the minimal base: Chromium is the largest CVE surface in the
# stack, so it belongs in a PUBLIC, SBOM'd, scanned image where it can be audited and externally
# scanned — not a private layer — and it must NOT be in `boardwalk/linux`, which stays minimal so a
# plain run doesn't carry a browser it never launches. It is NOT a per-run "flavor" the author picks:
# the platform makes it the hosted default; this repo just ships the artifact.
#
# Pinning policy (POLICY.md): the parent image is pinned by digest, npm tools by version ARG; the OS
# packages are locked in ENVIRONMENT.lock (re-derived + diffed in CI). No third-party apt repo.

FROM ghcr.io/boardwalk-labs/boardwalk-runner-linux:0.1.2@sha256:01e5f4030efa8f3dfe4a23ec21e01361b7b0a04740fe32337dfb1ba053525b6e

# Playwright MCP — the browser driver the agent talks to over MCP. Installed globally (into the base's
# node-owned npm prefix) so it runs FULLY OFFLINE: a hosted run's egress is proxied, so a runtime
# `npx` download would fail. The runner backend invokes its `playwright-mcp` bin directly.
ARG PLAYWRIGHT_MCP_VERSION=0.0.77

USER root

# The desktop + browser OS packages:
#  - xvfb: the headless X server the whole desktop renders into (the ambient screen).
#  - openbox: a minimal window manager (frames + focus, ~10 MB) — deliberately not a full DE.
#  - x11-utils (xdpyinfo, a readiness probe) + xauth (X authority for the display).
#  - chromium: the browser the session drives via CDP (pulls chromium-common + chromium-sandbox).
#  - fonts: liberation + noto (incl. color emoji) so pages/PDFs render real glyphs, not tofu.
# Versions are captured in ENVIRONMENT.lock (POLICY.md) — an upgrade is a reviewed lock diff.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  xvfb \
  openbox \
  x11-utils \
  xauth \
  chromium \
  fonts-liberation \
  fonts-noto-core \
  fonts-noto-color-emoji \
  && rm -rf /var/lib/apt/lists/*

# Pinned Playwright MCP into the shared node-owned global prefix (the same prefix the base's pnpm/tsx
# live in). `--help` proves the bin runs; chown keeps it writable by the unprivileged runtime user.
RUN npm install -g "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
  && playwright-mcp --help >/dev/null \
  && chown -R node:node /usr/local/share/npm-global

# A thin Chromium launcher the runner backend points BOARDWALK_BROWSER_CHROME_PATH at. It adds the
# flags a containerized / microVM Chromium needs: the VM is the sandbox, so --no-sandbox is correct
# HERE (scoped to this image, justified by the isolation boundary) rather than hardcoded in the
# generic backend; --disable-dev-shm-usage avoids the small-/dev/shm crash; --disable-gpu because the
# Xvfb screen has no GPU. The backend appends --remote-debugging-port, --user-data-dir, the start URL.
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# boardwalk/linux-desktop Chromium launcher — guest-appropriate baseline flags.' \
  'exec /usr/bin/chromium \' \
  '  --no-sandbox \' \
  '  --disable-dev-shm-usage \' \
  '  --disable-gpu \' \
  '  --disable-features=Translate \' \
  '  "$@"' \
  > /usr/local/bin/boardwalk-chromium \
  && chmod 0755 /usr/local/bin/boardwalk-chromium

# Bring up the on-screen desktop (Xvfb + WM) on $DISPLAY. The hosted worker / guest-init calls this so
# the desktop is up in the base snapshot (SCREEN_CAPTURE.md); it is also the smoke entrypoint. Blocks
# until X answers, then backgrounds the window manager. Screen geometry is overridable for the
# capture tier (BOARDWALK_DESKTOP_SCREEN, e.g. 1920x1080x24).
RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  ': "${DISPLAY:=:0}"' \
  'export DISPLAY' \
  'screen="${BOARDWALK_DESKTOP_SCREEN:-1280x800x24}"' \
  'Xvfb "$DISPLAY" -screen 0 "$screen" -nolisten tcp >/tmp/xvfb.log 2>&1 &' \
  'for _ in $(seq 1 100); do xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break; sleep 0.1; done' \
  'xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || { echo "Xvfb did not come up on $DISPLAY" >&2; cat /tmp/xvfb.log >&2; exit 1; }' \
  'openbox >/tmp/openbox.log 2>&1 &' \
  'echo "desktop up on $DISPLAY ($screen)"' \
  > /usr/local/bin/boardwalk-start-desktop \
  && chmod 0755 /usr/local/bin/boardwalk-start-desktop

# The browser-tier contract the runner backend reads (runner: src/runtime/browser_session_backend.ts):
#  - BOARDWALK_BROWSER_TIER=1       → the runner constructs the per-run browser-session manager.
#  - BOARDWALK_BROWSER_CHROME_PATH  → the program-owned CDP Chromium (the wrapper above).
#  - BOARDWALK_BROWSER_MCP_COMMAND  → run the pinned, pre-installed Playwright MCP directly (offline).
#  - DISPLAY                        → the screen Chromium renders on (headful, so capture can mirror it).
ENV BOARDWALK_BROWSER_TIER=1 \
  BOARDWALK_BROWSER_CHROME_PATH=/usr/local/bin/boardwalk-chromium \
  BOARDWALK_BROWSER_MCP_COMMAND=playwright-mcp \
  DISPLAY=:0

# Back to the unprivileged runtime user + the /workspace contract the base established. Derived images
# (the platform worker layer) may switch to root for their own layer but MUST return to a non-root user.
USER node
WORKDIR /workspace
ENV HOME=/workspace

CMD ["bash"]
