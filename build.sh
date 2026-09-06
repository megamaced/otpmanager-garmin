#!/usr/bin/env bash
# Builds a signed .prg for each supported device, and optionally runs the tests.
#
#   ./build.sh          build every device
#   ./build.sh test     build the unit-test binary and run it in the simulator
#
# The simulator needs webkit2gtk-4.0, which no current distro ships; see
# README.md for the container that provides it.
set -euo pipefail

SDK=$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg)
KEY=${DEVELOPER_KEY:-$HOME/.Garmin/keys/developer_key.der}
DEVICES=(venu3s venu3 vivoactive5)

mkdir -p build

if [ "${1:-}" = "test" ]; then
    "$SDK/bin/monkeyc" -f monkey.jungle -o build/test.prg -y "$KEY" \
        -d venu3s -w -l 3 --unit-test
    exec "$SDK/bin/monkeydo" build/test.prg venu3s -t
fi

for device in "${DEVICES[@]}"; do
    printf '%-14s' "$device"
    "$SDK/bin/monkeyc" -f monkey.jungle -o "build/otpmanager-$device.prg" \
        -y "$KEY" -d "$device" -w -l 3
done
