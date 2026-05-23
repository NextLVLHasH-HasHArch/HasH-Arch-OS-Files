#!/usr/bin/env bash
# Runs cava and keeps only the latest frame in a small file the wallpaper polls.
# Atomic write (tmp + mv) so the wallpaper never reads a half-written frame.
#
# Follows the DEFAULT audio sink: cava resolves `source = auto` only at startup,
# so when you switch outputs (e.g. connect Bluetooth headphones) it would keep
# reading the OLD sink's monitor and the visualizer flatlines. We watch for
# default-sink changes and restart cava so it re-binds to the new sink's monitor.
# (Always the sink monitor — never the microphone.)
set -uo pipefail
out="${XDG_RUNTIME_DIR:-/tmp}/cava-wallpaper.dat"
conf="$HOME/.config/cava/wallpaper.conf"

run_pipe() {
    cava -p "$conf" | while IFS= read -r line; do
        printf '%s' "$line" > "$out.tmp" && mv -f "$out.tmp" "$out"
    done
}
stop_cava() { pkill -f "cava -p $conf" 2>/dev/null || true; }

trap 'stop_cava; exit 0' TERM INT

stop_cava            # clear any stale instance from a previous run
run_pipe &

# Restart cava whenever the default sink changes (Bluetooth connect/disconnect,
# HDMI, USB DAC, …). Killing cava closes the pipe, the old reader ends, and a
# fresh cava re-resolves `source = auto` to the NEW default sink's monitor.
last="$(pactl get-default-sink 2>/dev/null || true)"
pactl subscribe 2>/dev/null | while IFS= read -r ev; do
    case "$ev" in
        *"on server"*|*"on sink"*)
            cur="$(pactl get-default-sink 2>/dev/null || true)"
            if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
                last="$cur"
                stop_cava
                sleep 0.3        # let the new sink settle before re-binding
                run_pipe &
            fi
            ;;
    esac
done
