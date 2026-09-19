#!/usr/bin/env bash
# Builds a signed .prg for each supported device, and optionally runs the tests
# or packages the app for the store.
#
#   ./build.sh          build every device
#   ./build.sh local [device]
#                       one .prg with local.properties compiled in
#   ./build.sh test     build the unit-test binary and run it in the simulator
#   ./build.sh export   a .iq for the store, under the production app id
#   ./build.sh beta     a .iq for the store's Beta App slot, under BETA_APP_ID
#
# The simulator needs webkit2gtk-4.0, which no current distro ships; see
# README.md for the container that provides it.
set -euo pipefail

SDK=$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg)
KEY=${DEVELOPER_KEY:-$HOME/.Garmin/keys/developer_key.der}
# A representative device per launcher-icon size, plus the screen extremes:
# 240 px round through 466 px round and the one rectangular watch. Building
# all 44 takes minutes and tells you nothing more — every device shares the
# same source, and only the icon mapping differs. `export` builds the lot.
DEVICES=(fenix7s vivoactive6 vivoactive5 epix2 venu3s venu445mm fenix9pro51mm venux1)

# A beta upload has to carry a different app id from the production one, so that
# the store treats it as a separate listing. Not a secret, and not the signing
# key: the same developer key signs both.
BETA_APP_ID=fb74c5e3731a4959a98457235983fdbf

mkdir -p build

# Restores a file on the way out, including on failure. Not `git checkout`:
# that would also discard uncommitted edits to the same file, which during
# development is most of them.
#
# Refuses to start when a backup is already there. One would mean an earlier
# build died before its trap ran, so the working copy is the patched one — and
# overwriting the backup with it would make the damage permanent on the next
# successful build.
restore_on_exit() {
    if [ -e "$1.orig" ]; then
        echo "$1.orig already exists: an earlier build did not finish." >&2
        echo "Check it, then 'mv $1.orig $1' to undo that build's patch." >&2
        exit 1
    fi
    cp "$1" "$1.orig"
    # shellcheck disable=SC2064
    trap "mv '$1.orig' '$1'" EXIT
}

case "${1:-}" in
local)
    # Sideloaded apps get no settings UI from Garmin, so a personal build bakes
    # the values from local.properties in as defaults. With a `pin` set they are
    # sealed first, and the .prg carries ciphertext rather than credentials.
    # Only the watch in hand needs building, and it is rarely the default one:
    # the app supports 44 devices and nobody sideloads to all of them.
    device=${2:-venu3s}
    if [ ! -d "$HOME/.Garmin/ConnectIQ/Devices/$device" ]; then
        echo "no device profile for '$device' — download it in the SDK Manager" >&2
        exit 1
    fi

    # The baked values are credentials, so nothing tracked is written: the
    # build reads its resources from a private copy under build/ instead.
    # Patching resources/properties.xml in place and restoring it afterwards
    # worked until it didn't — a build killed between the two leaves a password
    # in a file git tracks, ready to be staged, indexed or backed up.
    #
    # Jungle paths resolve relative to the jungle file, so the override has to
    # sit at the repository root. Later files win, and the per-device icon
    # lines pick up the new base.resourcePath through $(base.resourcePath).
    LOCAL_RES=build/local-resources
    LOCAL_JUNGLE=.local-build.jungle
    rm -rf "$LOCAL_RES"
    mkdir -p "$LOCAL_RES"
    chmod 700 "$LOCAL_RES"
    trap 'rm -rf "$LOCAL_RES" "$LOCAL_JUNGLE"' EXIT
    cp -r resources/. "$LOCAL_RES/"

    python3 tools/bake-properties.py --out "$LOCAL_RES/properties.xml"
    printf 'base.resourcePath = %s\n' "$LOCAL_RES" > "$LOCAL_JUNGLE"

    "$SDK/bin/monkeyc" -f "monkey.jungle;$LOCAL_JUNGLE" -o "build/otpmanager-$device.prg" \
        -y "$KEY" -d "$device" -w -l 3
    echo "built build/otpmanager-$device.prg with local.properties baked in"
    ;;

test)
    # The build tools first: they are the only part written in something other
    # than Monkey C, and a regression there corrupts a credential silently.
    python3 -m unittest discover -s tools -p 'test_*.py' -q
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
    echo "usage: $0 [local [device]|test|export|beta]" >&2
    exit 1
    ;;
esac
