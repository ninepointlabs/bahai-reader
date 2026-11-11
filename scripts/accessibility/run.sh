#!/bin/bash
Xvfb :99 -screen 0 1400x900x24 >/dev/null 2>&1 & export DISPLAY=:99 BAHAI_READER_SHELL=${SHELL_KIND:-adwaita} NO_AT_BRIDGE=0 GTK_A11Y=atspi
sleep 1.5
dbus-run-session -- bash -c '
  /usr/lib/at-spi-bus-launcher --launch-immediately >/tmp/bus.log 2>&1 & sleep 1.5
  ( if [ -n "$ORCA" ]; then speech-dispatcher -d -s >/dev/null 2>&1; orca --replace --debug-file=/out/orca-debug.log >/tmp/orca.out 2>&1 & fi )
  sleep 2
  python3 /a/app.py /repo >/tmp/app.log 2>&1 &
  python3 /a/audit.py
  sleep 1; grep -v -i warn /tmp/app.log | tail -5
'
