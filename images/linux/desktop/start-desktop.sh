#!/usr/bin/env bash
# Ambient desktop bring-up. The platform's runtime layer execs this before the worker when the
# desktop is enabled (BOARDWALK_BROWSER_TIER=1):
# Xvfb -> openbox (Boardwalk flat dark theme) -> wallpaper (feh, after the WM so it isn't
# cleared) -> dock (tint2) -> a live run-output terminal (sakura) that tails the runner's
# redacted local log mirror (BOARDWALK_RUN_LOG_FILE), so the live-view/recording shows the run
# working. Best-effort throughout — a piece that fails to start must never stop the run.
set -uo pipefail
: "${DISPLAY:=:0}"
export DISPLAY

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
for _ in $(seq 1 100); do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  sleep 0.1
done
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || {
  echo "Xvfb-failed" >&2
  exit 1
}

# Terminal styling, written at runtime so it lands in whichever user's HOME runs the desktop:
# GTK css pads the vte widget (sakura has no padding setting of its own); sakura.conf sets the
# font + a dark colorset matching the openbox/dock chrome.
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$CONF_DIR/gtk-3.0" "$CONF_DIR/sakura" 2>/dev/null || true
printf 'vte-terminal { padding: 12px 16px; }\n' >"$CONF_DIR/gtk-3.0/gtk.css" 2>/dev/null || true
cat >"$CONF_DIR/sakura/sakura.conf" <<'SAKURA' 2>/dev/null || true
[sakura]
colorset1_fore=rgb(219,232,242)
colorset1_back=rgb(14,19,26)
colorset1_curs=rgb(125,200,255)
palette=tango
font=JetBrains Mono 11
show_always_first_tab=No
scrollbar=false
less_questions=true
SAKURA

openbox >/tmp/openbox.log 2>&1 &
sleep 1
feh --no-fehbg --bg-fill /usr/share/boardwalk/wallpaper.jpg >/tmp/feh.log 2>&1 || true
tint2 -c /etc/xdg/tint2/tint2rc >/tmp/tint2.log 2>&1 &

# Live run-output terminal — an on-screen "app window" tailing the runner's redacted event mirror
# (boardwalk-run-tail). Size + top-right position come from the openbox rc.xml application rule.
# sakura's -x wants ONE command string (its multi-arg -e exits silently — do not use it).
# SUPERVISED in a loop: the terminal's PTY + child (tail) do NOT survive the microVM
# snapshot/restore, so it exits on wake; the loop relaunches it (a fresh PTY, now tailing the
# restored run's log).
touch "${BOARDWALK_RUN_LOG_FILE:-/tmp/boardwalk-run.log}" 2>/dev/null || true
(
  while true; do
    sakura -x boardwalk-run-tail >/dev/null 2>&1
    sleep 1
  done
) >/tmp/term.log 2>&1 &

echo "desktop-up-on-$DISPLAY"
