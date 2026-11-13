#!/bin/sh
# Build zen-layer-hid and install it with the Hammerspoon module into the
# Hammerspoon config directory (~/.hammerspoon unless MJConfigFile moves it):
#   <configdir>/bin/zen-layer-hid
#   <configdir>/zen_layer.lua
# Then add `require("zen_layer").start()` to <configdir>/init.lua.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
config_file=$(defaults read org.hammerspoon.Hammerspoon MJConfigFile 2>/dev/null || true)
if [ -n "$config_file" ]; then
    dest=$(dirname "$(eval echo "$config_file")")
else
    dest="$HOME/.hammerspoon"
fi
mkdir -p "$dest/bin"

# The Command Line Tools can ship an SDK newer than their own swiftc; fall
# back to older SDKs until one builds.
build() {
    swiftc -O ${1:+-sdk "$1"} -o "$dest/bin/zen-layer-hid" "$here/zen-layer-hid/main.swift"
}
if ! build "" 2>/dev/null; then
    sdk_dir="$(xcrun --show-sdk-path)/.."
    built=
    for sdk in $(ls -d "$sdk_dir"/MacOSX[0-9]*.sdk | sort -rV); do
        if build "$sdk" 2>/dev/null; then built=$sdk; break; fi
    done
    [ -n "$built" ] || { echo "swiftc failed with every SDK in $sdk_dir" >&2; build ""; }
fi

cp "$here/hammerspoon/zen_layer.lua" "$dest/zen_layer.lua"
echo "installed: $dest/bin/zen-layer-hid, $dest/zen_layer.lua"
