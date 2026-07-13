#!/usr/bin/env bash
# The command the run-output terminal runs (sakura -x boardwalk-run-tail): set the window title
# (sakura has no title flag — OSC 0 escape instead), print the idle banner, then follow the
# runner's redacted local log mirror.
printf '\033]0;Run output\007\033[1;36mBoardwalk — waiting for run activity…\033[0m\n'
exec tail -n +1 -F "${BOARDWALK_RUN_LOG_FILE:-/tmp/boardwalk-run.log}"
