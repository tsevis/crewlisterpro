#!/bin/zsh
# Builds Contents/Resources/AppIcon.icns from Resources/AppIcon.png.
#
# macOS asks for ten representations; shipping fewer makes the Dock, Finder and
# the Cmd-Tab switcher scale whichever one they find, which reads as blurry.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/Resources/AppIcon.png}"
DESTINATION="${2:-$ROOT/.build/AppIcon.icns}"

if [[ ! -f "$SOURCE" ]]; then
  echo "Icon source is missing: $SOURCE" >&2
  exit 1
fi

read -r width height <<<"$(sips -g pixelWidth -g pixelHeight "$SOURCE" | awk '/pixel/ {printf "%s ", $2}')"
if [[ "$width" != "$height" ]]; then
  echo "Icon must be square; $SOURCE is ${width}x${height}" >&2
  exit 1
fi
if (( width < 1024 )); then
  echo "Icon must be at least 1024x1024; $SOURCE is ${width}x${width}" >&2
  exit 1
fi

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$WORK"' EXIT

# Apply the macOS icon grid — 824pt rounded body on a 1024pt canvas, with a
# shadow — unless the artwork already carries it. The source stays flat, so the
# platform treatment can change without anyone re-cutting the original.
SHAPED="$SOURCE"
if [[ "${CREWLISTR_ICON_NO_MASK:-0}" != "1" ]]; then
  SHAPED="$WORK/shaped.png"
  swift "$ROOT/scripts/mask-icon.swift" "$SOURCE" "$SHAPED"
fi

for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
            "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  size="${spec%%:*}"
  name="${spec#*:}"
  sips -z "$size" "$size" "$SHAPED" --out "$ICONSET/$name.png" >/dev/null
done

mkdir -p "$(dirname "$DESTINATION")"
iconutil --convert icns "$ICONSET" --output "$DESTINATION"
echo "Wrote $DESTINATION"
