#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Offline contract smoke for boardwalk/linux-desktop. Proves the browser tier wires together end to
# end INSIDE the image with NO network (the pins must not lazy-download): the desktop comes up, the
# program-owned Chromium exposes a CDP endpoint on the screen, and the pinned Playwright MCP attaches
# to it over CDP and serves HTTP. Run in CI (docker run --network none) and locally the same way.
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"

echo "== identity + contract env =="
[ "$(whoami)" = "node" ] || { echo "expected to run as 'node'" >&2; exit 1; }
[ "${BOARDWALK_BROWSER_TIER:-}" = "1" ] || { echo "BOARDWALK_BROWSER_TIER not set" >&2; exit 1; }
[ -x "${BOARDWALK_BROWSER_CHROME_PATH:-}" ] || { echo "chrome wrapper not executable" >&2; exit 1; }
command -v "${BOARDWALK_BROWSER_MCP_COMMAND:-playwright-mcp}" >/dev/null || { echo "playwright-mcp missing" >&2; exit 1; }

echo "== bring up the desktop =="
boardwalk-start-desktop

echo "== program-owned CDP Chromium (headful on $DISPLAY) =="
profile="$(mktemp -d)"
"$BOARDWALK_BROWSER_CHROME_PATH" --remote-debugging-port=9222 --user-data-dir="$profile" \
  --no-first-run about:blank >/tmp/chromium.log 2>&1 &
for _ in $(seq 1 150); do curl -sf http://127.0.0.1:9222/json/version >/dev/null 2>&1 && break; sleep 0.1; done
curl -sf http://127.0.0.1:9222/json/version >/dev/null 2>&1 \
  || { echo "chromium CDP did not come up" >&2; cat /tmp/chromium.log >&2; exit 1; }
echo "chromium CDP up"

echo "== Playwright MCP attached over CDP (HTTP mode) =="
"$BOARDWALK_BROWSER_MCP_COMMAND" --port 9333 --host 127.0.0.1 --allowed-hosts '*' \
  --cdp-endpoint http://127.0.0.1:9222 >/tmp/pwmcp.log 2>&1 &
code=""
for _ in $(seq 1 150); do
  code="$(curl -so /dev/null -w '%{http_code}' http://127.0.0.1:9333/mcp 2>/dev/null || true)"
  [ -n "$code" ] && [ "$code" != "000" ] && break
  sleep 0.1
done
# Any HTTP response proves the server is listening — the /mcp endpoint answers a bare GET with a 4xx
# (its localhost/DNS-rebinding guard), which is exactly the "up" signal the runner backend polls for.
case "$code" in
  2* | 4*) echo "playwright-mcp up (HTTP $code)" ;;
  *) echo "playwright-mcp did not come up (got '$code')" >&2; cat /tmp/pwmcp.log >&2; exit 1 ;;
esac

echo "linux-desktop smoke OK"
