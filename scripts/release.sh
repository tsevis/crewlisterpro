#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/arm64-apple-macosx/release/CrewListrProMac"
OUTPUT="$ROOT/dist"
APP="$OUTPUT/CrewListr Pro.app"

swift build -c release --package-path "$ROOT"
rm -rf "$OUTPUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BUILD" "$APP/Contents/MacOS/CrewListrProMac"
SQLCIPHER_PREFIX="$(brew --prefix sqlcipher)"
OPENSSL4_PREFIX="$(brew --prefix openssl@4)"
cp "$SQLCIPHER_PREFIX/lib/libsqlcipher.dylib" "$APP/Contents/Frameworks/libsqlcipher.dylib"
cp "$OPENSSL4_PREFIX/lib/libcrypto.4.dylib" "$APP/Contents/Frameworks/libcrypto.4.dylib"
install_name_tool -change "$SQLCIPHER_PREFIX/lib/libsqlcipher.dylib" "@executable_path/../Frameworks/libsqlcipher.dylib" "$APP/Contents/MacOS/CrewListrProMac"
install_name_tool -change "$OPENSSL4_PREFIX/lib/libcrypto.4.dylib" "@loader_path/libcrypto.4.dylib" "$APP/Contents/Frameworks/libsqlcipher.dylib"
LLAMA_SERVER="${CREWLISTR_LLAMA_SERVER:-$(command -v llama-server || true)}"
if [[ -z "$LLAMA_SERVER" || ! -x "$LLAMA_SERVER" ]]; then
  echo "llama-server is required to package local Qwen3-VL inference. Set CREWLISTR_LLAMA_SERVER." >&2
  exit 1
fi
cp "$LLAMA_SERVER" "$APP/Contents/Resources/llama-server"
for library in libssl.3.dylib libcrypto.3.dylib; do
  source="/opt/homebrew/opt/openssl@3/lib/$library"
  if [[ ! -f "$source" ]]; then
    echo "Required llama-server dependency is missing: $source" >&2
    exit 1
  fi
  cp "$source" "$APP/Contents/Frameworks/$library"
  install_name_tool -change "/opt/homebrew/opt/openssl@3/lib/$library" "@executable_path/../Frameworks/$library" "$APP/Contents/Resources/llama-server"
done
# install_name_tool rewrites load commands, which invalidates the linker's
# ad-hoc signature. On Apple Silicon an invalid signature is fatal: the kernel
# SIGKILLs the process at exec, with no output. Re-sign every rewritten binary.
codesign --force --sign - "$APP/Contents/Frameworks/libsqlcipher.dylib"
codesign --force --sign - "$APP/Contents/Resources/llama-server"

# Product metadata is read from Sources/CrewListrProMac/Version.swift so the
# bundle can never disagree with the binary it wraps.
version_value() {
  grep -E "static let $1 = \"" "$ROOT/Sources/CrewListrProMac/Version.swift" | head -1 | sed -E 's/.*= "(.*)"/\1/'
}
SHORT_VERSION="$(version_value short)"
BUILD_VERSION="$(version_value build)"
BUNDLE_ID="$(version_value bundleIdentifier)"
APP_NAME="$(version_value name)"
TAGLINE="$(version_value tagline)"
CATEGORY="$(version_value applicationCategory)"
ICON_FILE="$(version_value iconFile)"
COPYRIGHT="$(version_value copyright)"
for required in SHORT_VERSION BUILD_VERSION BUNDLE_ID APP_NAME CATEGORY ICON_FILE; do
  if [[ -z "${(P)required}" ]]; then
    echo "Could not read $required from Version.swift" >&2
    exit 1
  fi
done

# SwiftPM emits the target's `resources:` as a bundle beside the executable.
# `Bundle.module` finds it in Contents/Resources of a packaged app, but only if
# it is put there — without this the brand marks silently fall back to a glyph.
RESOURCE_BUNDLE="$(dirname "$BUILD")/CrewListrProMac_CrewListrProMac.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing $RESOURCE_BUNDLE; the executable target's resources did not build." >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"

"$ROOT/scripts/make-icon.sh" "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/$ICON_FILE.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CrewListrProMac</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_VERSION}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>${CATEGORY}</string>
    <key>CFBundleIconFile</key><string>${ICON_FILE}</string>
    <key>CFBundleIconName</key><string>${ICON_FILE}</string>
    <key>NSHumanReadableCopyright</key><string>${COPYRIGHT}</string>
    <key>NSHumanReadableDescription</key><string>${TAGLINE}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
EOF

# The bundle seal must be applied last, after Info.plist and every payload is
# in place, or `codesign -v` reports a sealed-resource mismatch and macOS
# refuses to launch the app.
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP"

# Give the mounted volume the app's own icon rather than the generic disk.
cp "$APP/Contents/Resources/$ICON_FILE.icns" "$APP/../.VolumeIcon.icns" 2>/dev/null || true

hdiutil create -volname "$APP_NAME $SHORT_VERSION" -srcfolder "$APP" -ov -format UDZO "$OUTPUT/CrewListr-Pro-$SHORT_VERSION.dmg"
echo "Built $APP_NAME $SHORT_VERSION ($BUILD_VERSION) -> $OUTPUT"
