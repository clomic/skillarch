#!/bin/bash -x

# Terminate already running bar instances
killall -q polybar || true

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

MONITORS=$(polybar --list-monitors)
MONITOR_PRIMARY=$(echo "$MONITORS" | grep "primary" | cut -d":" -f1 || true)
MONITOR_EXTRA=$(echo "$MONITORS" | grep -v "primary" | cut -d":" -f1 || true)

# Start main polybar with tray
MONITOR=${MONITOR_PRIMARY:-${MONITOR_EXTRA%% *} MOD_RIGHT="systray microphone pulseaudio memory cpu filesystem battery wlan eth date" polybar main &
for m in $MONITOR_EXTRA; do
    MONITOR=$m MOD_RIGHT="microphone pulseaudio memory cpu filesystem battery wlan eth date" polybar main &
done
