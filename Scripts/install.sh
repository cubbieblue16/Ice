#!/bin/bash
#
# Builds Ice and installs it, signed.
#
# Replaces the project's "Copy to Applications" build phase, which cannot work:
# Xcode signs a target *after* its script phases run, so that phase always copies
# an unsigned bundle. macOS then refuses to launch it — "Launchd job spawn
# failed" — and the freshly built app appears simply broken.
#
# Installs to /Applications by default, which needs write access to it (an administrator account
# usually has it). macOS 27 resolves a menu bar item's application only under /Applications, so
# ~/Applications is not supported there; setting DEST elsewhere is at your own risk.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-/Applications}"
DERIVED="${DERIVED:-/tmp/ice-build}"

# Signing. A "Developer ID Application" identity in the keychain is used when one exists (or
# name one with SIGN_IDENTITY="Developer ID Application: Name (TEAM)"). Signing does not decide
# whether hiding works on macOS 27 (the MenuBarItemService helper holds the assertions, and a
# holder's own items are not dropped, whoever signs it). It decides whether TCC grants survive:
# every ad hoc rebuild changes the code hash, which makes TCC forget the Screen Recording grant,
# while a Developer ID signature keeps a stable designated requirement across rebuilds.
#
# Without such an identity the build falls back to ad hoc, with the hardened runtime off on
# purpose: the hardened runtime then refuses to load Sparkle, which carries a team of its own
# ("mapping process and mapped file (non-platform) have different Team IDs"). `codesign --verify
# --deep --strict` passes all the same, so the script used to install a bundle that could not
# launch for anyone without a team (reported on jordanbaird/Ice#1006 by @Theralley). The project
# names the upstream team and an "Apple Development" identity that only its owner holds, so the
# identity is forced to ad hoc ("-") and the team cleared, as release.yml does.
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^ *[0-9]+\) [0-9A-F]+ "(Developer ID Application: [^"]+)".*/\1/p' | head -1)}"
if [ -n "$SIGN_IDENTITY" ]; then
    TEAM="$(printf '%s' "$SIGN_IDENTITY" | sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p')"
    [ -n "$TEAM" ] || { echo "error: cannot read a team id from \"$SIGN_IDENTITY\"" >&2; exit 1; }
    echo "==> Building, signed with: $SIGN_IDENTITY"
    SIGN_ARGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" "DEVELOPMENT_TEAM=$TEAM"
        ENABLE_HARDENED_RUNTIME=YES)
else
    echo "==> Building, signed ad hoc (no Developer ID Application identity in the keychain)"
    SIGN_ARGS=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGNING_REQUIRED=NO
        ENABLE_HARDENED_RUNTIME=NO)
fi
xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    ARCHS=arm64 "${SIGN_ARGS[@]}" \
    | tail -3

APP="$DERIVED/Build/Products/Release/Ice 27.0.app"
[ -d "$APP" ] || { echo "error: no product at $APP" >&2; exit 1; }

echo "==> Verifying the signature before installing"
# The whole point: never install something that will not launch.
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|^Authority=' | sed 's/^/    /'

echo "==> Installing to $DEST"
if pgrep -x "Ice 27.0" >/dev/null 2>&1; then
    osascript -e 'tell application id "tech.kuta.Ice27" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "Ice 27.0" >/dev/null 2>&1 || break
        sleep 0.3
    done
    pgrep -x "Ice 27.0" >/dev/null 2>&1 && pkill -x "Ice 27.0" || true
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/Ice 27.0.app"
# ditto, not cp: it preserves the code signature.
ditto "$APP" "$DEST/Ice 27.0.app"

echo "==> Verifying the installed copy"
codesign --verify --deep --strict "$DEST/Ice 27.0.app"

open -a "$DEST/Ice 27.0.app"
echo "==> Running from $DEST/Ice 27.0.app"
