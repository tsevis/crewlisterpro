#!/bin/zsh
# Builds the distributable disk image.
#
# usage: make-dmg.sh <app> <volume name> <output dmg> [read-me file]
#
# The volume icon used to be copied to dist/.VolumeIcon.icns while hdiutil was
# given the .app itself as its source folder, so the icon sat next to the image
# instead of inside it and every disk mounted with the generic white icon. A
# staging directory fixes that, and earns its keep a second time: it is also
# where the /Applications symlink lives.
#
# That symlink is not decoration. An app opened from the disk image, or left in
# Downloads, runs under App Translocation — macOS copies it to a randomised
# read-only mount — and anything that resolves a path relative to its own
# bundle, which here means the bundled llama-server, is then looking in the
# wrong place. Dragging the app to /Applications is what stops that happening.
set -euo pipefail

APP="$1"
VOLUME_NAME="$2"
OUTPUT_DMG="$3"
READ_ME="${4:-}"

STAGING="$(mktemp -d)"
MOUNT="$(mktemp -d)"
WRITABLE="$STAGING.dmg"

cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$STAGING" "$MOUNT"
  rm -f "$WRITABLE"
}
trap cleanup EXIT

# ditto, not cp: it preserves the code signature, and a seal broken in transit
# is SIGKILLed at launch with nothing in the logs.
ditto "$APP" "$STAGING/${APP:t}"
ln -s /Applications "$STAGING/Applications"
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] &&
  cp "$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
[[ -n "$READ_ME" && -f "$READ_ME" ]] && cp "$READ_ME" "$STAGING/${READ_ME:t}"

# Read/write first: the custom-icon attribute has to be set on a mounted
# volume, and a compressed image cannot be written to.
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDRW "$WRITABLE" >/dev/null
hdiutil attach "$WRITABLE" -nobrowse -mountpoint "$MOUNT" >/dev/null

# macOS ignores .VolumeIcon.icns unless the volume root carries the custom-icon
# attribute, and only SetFile sets it. SetFile ships with Xcode, so a machine
# with just the Command Line Tools gets the generic icon rather than a failure.
SET_FILE="$(xcrun --find SetFile 2>/dev/null || true)"
if [[ -n "$SET_FILE" && -x "$SET_FILE" ]]; then
  "$SET_FILE" -a C "$MOUNT"
else
  echo "note: SetFile not found, so the image keeps the generic volume icon."
fi

hdiutil detach "$MOUNT" -quiet
hdiutil convert "$WRITABLE" -format UDZO -o "$OUTPUT_DMG" -ov >/dev/null
echo "Disk image: $OUTPUT_DMG"
