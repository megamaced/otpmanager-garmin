#!/usr/bin/env bash
# Builds a signed .prg for each supported device, and optionally runs the tests
# or packages the app for the store.
#
#   ./build.sh          build every device
#   ./build.sh local    one .prg with local.properties compiled in
#   ./build.sh test     build the unit-test binary and run it in the simulator
#   ./build.sh export   a .iq for the store, under the production app id
#   ./build.sh beta     a .iq for the store's Beta App slot, under BETA_APP_ID
#
# The simulator needs webkit2gtk-4.0, which no current distro ships; see
# README.md for the container that provides it.
set -euo pipefail

SDK=$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg)
KEY=${DEVELOPER_KEY:-$HOME/.Garmin/keys/developer_key.der}
DEVICES=(venu3s venu3 vivoactive5)

# A beta upload has to carry a different app id from the production one, so that
# the store treats it as a separate listing. Not a secret, and not the signing
# key: the same developer key signs both.
BETA_APP_ID=fb74c5e3731a4959a98457235983fdbf

mkdir -p build

# Restores a file on the way out, including on failure. Not `git checkout`:
# that would also discard uncommitted edits to the same file, which during
# development is most of them.
restore_on_exit() {
    cp "$1" "$1.orig"
    # shellcheck disable=SC2064
    trap "mv '$1.orig' '$1'" EXIT
}

case "${1:-}" in
local)
    # Sideloaded apps get no settings UI from Garmin, so a personal build bakes
    # the values from local.properties in as defaults. With a `pin` set they are
    # sealed first, and the .prg carries ciphertext rather than credentials.
    restore_on_exit resources/properties.xml
    python3 tools/bake-properties.py
    "$SDK/bin/monkeyc" -f monkey.jungle -o build/otpmanager-venu3s.prg \
        -y "$KEY" -d venu3s -w -l 3
    echo "built build/otpmanager-venu3s.prg with local.properties baked in"
    ;;

test)
    "$SDK/bin/monkeyc" -f monkey.jungle -o build/test.prg -y "$KEY" \
        -d venu3s -w -l 3 --unit-test
    exec "$SDK/bin/monkeydo" build/test.prg venu3s -t
    ;;

export)
    # Every device in the manifest, in one archive. The committed property
    # defaults are empty, which is what a store build wants: the wearer fills
    # them in from Garmin Connect.
    "$SDK/bin/monkeyc" -f monkey.jungle -o build/otpmanager.iq -y "$KEY" -e -w -l 3
    echo "built build/otpmanager.iq"
    ;;

beta)
    restore_on_exit manifest.xml
    sed -i "s/id=\"[0-9a-f]\{32\}\"/id=\"$BETA_APP_ID\"/" manifest.xml
    "$SDK/bin/monkeyc" -f monkey.jungle -o build/otpmanager-beta.iq -y "$KEY" -e -w -l 3
    echo "built build/otpmanager-beta.iq as app id $BETA_APP_ID"
    echo "upload it at developer.garmin.com with the Beta App box ticked"
    ;;

"")
    for device in "${DEVICES[@]}"; do
        printf '%-14s' "$device"
        "$SDK/bin/monkeyc" -f monkey.jungle -o "build/otpmanager-$device.prg" \
            -y "$KEY" -d "$device" -w -l 3
    done
    ;;

*)
    echo "usage: $0 [local|test|export|beta]" >&2
    exit 1
    ;;
esac
