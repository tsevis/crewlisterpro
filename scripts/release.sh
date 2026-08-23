#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/arm64-apple-macosx/release/CrewListrProMac"
OUTPUT="$ROOT/dist"
APP="$OUTPUT/CrewListr Pro.app"
INSTALLED="/Applications/CrewListr Pro.app"

# Building into dist/ and installing into /Applications used to be unrelated
# acts, so the two drifted: a superseded build sat in /Applications for weeks,
# claiming the same bundle identifier as this one. LaunchServices answered
# every launch with the stale copy — including `open` on the correct path —
# and its own unrelated failure was read as this app being broken.
# Ad-hoc signing makes every rebuild a different application to macOS, because
# an ad-hoc identity IS the code hash. Anything granted to the app personally —
# a Keychain item's access list, a TCC permission — is granted to one build and
# lost with the next. Signing with a certificate makes the designated
# requirement name the certificate instead, so it holds across rebuilds.
# scripts/create-signing-identity.sh creates it; without one, ad-hoc still works.
SIGNING_IDENTITY="${CREWLISTR_SIGNING_IDENTITY:-CrewListr Pro Local Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY"; then
  SIGN_AS="$SIGNING_IDENTITY"
else
  SIGN_AS="-"
fi

INSTALL=0
for argument in "$@"; do
  case "$argument" in
    --install) INSTALL=1 ;;
    -h|--help)
      echo "usage: release.sh [--install]"
      echo "  --install   after building, replace $INSTALLED with this build"
      exit 0
      ;;
    *) echo "Unknown option: $argument" >&2; exit 2 ;;
  esac
done

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
codesign --force --sign "$SIGN_AS" "$APP/Contents/Frameworks/libsqlcipher.dylib"
codesign --force --sign "$SIGN_AS" "$APP/Contents/Resources/llama-server"

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

# Finder metadata and resource forks travel with a copied file and make
# codesign refuse the bundle outright: "resource fork, Finder information, or
# similar detritus not allowed". Strip them before sealing.
# Homebrew's dylibs are copied in mode 444, and xattr cannot clear attributes
# on a file it cannot write.
chmod -R u+w "$APP"
xattr -cr "$APP"

# The bundle seal must be applied last, after Info.plist and every payload is
# in place, or `codesign -v` reports a sealed-resource mismatch and macOS
# refuses to launch the app.
codesign --force --deep --sign "$SIGN_AS" "$APP"
codesign --verify --strict "$APP"
if [[ "$SIGN_AS" == "-" ]]; then
  echo "NOTE: signed ad-hoc; no '$SIGNING_IDENTITY' identity found."
  echo "      Each rebuild will be a new app identity to macOS."
  echo "      Run: scripts/create-signing-identity.sh"
else
  echo "Signed with $SIGN_AS"
fi

# Give the mounted volume the app's own icon rather than the generic disk.
cp "$APP/Contents/Resources/$ICON_FILE.icns" "$APP/../.VolumeIcon.icns" 2>/dev/null || true

hdiutil create -volname "$APP_NAME $SHORT_VERSION" -srcfolder "$APP" -ov -format UDZO "$OUTPUT/CrewListr-Pro-$SHORT_VERSION.dmg"
echo "Built $APP_NAME $SHORT_VERSION ($BUILD_VERSION) -> $OUTPUT"

installed_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist" 2>/dev/null || echo "unreadable"
}

if (( INSTALL )); then
  # A running copy holds the executable and the encrypted store open. Replacing
  # it underneath itself leaves a process running code that no longer exists on
  # disk, which is exactly the state that is impossible to reason about later.
  if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -f "$INSTALLED" >/dev/null 2>&1; then
    echo "Quitting the running copy before replacing it"
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || pkill -f "$INSTALLED" || true
  fi

  # Moved, never deleted. The copy being replaced may be the only build of a
  # version that is not in git, and this script must not be the thing that
  # loses it.
  if [[ -e "$INSTALLED" ]]; then
    ARCHIVE="$HOME/.Trash/CrewListr Pro $(installed_version) $(date +%Y-%m-%d-%H%M%S).app"
    mv "$INSTALLED" "$ARCHIVE"
    echo "Moved the previous $INSTALLED to the Trash as $(basename "$ARCHIVE")"
  fi

  # ditto, not cp: it preserves the code signature, and an app whose seal is
  # broken in transit is SIGKILLed at launch with nothing in the logs.
  ditto "$APP" "$INSTALLED"
  codesign --verify --strict "$INSTALLED"

  # LaunchServices caches which bundle owns an identifier. Without this it can
  # keep answering with the copy that was just moved to the Trash.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED"
  echo "Installed $APP_NAME $SHORT_VERSION -> $INSTALLED"
elif [[ -e "$INSTALLED" ]] && [[ "$(installed_version)" != "$SHORT_VERSION" ]]; then
  # Not an error: building without installing is legitimate. But the two copies
  # answer to one bundle identifier, so the reader should know which one a
  # double-click will actually open.
  echo ""
  echo "WARNING: $INSTALLED is version $(installed_version), not the $SHORT_VERSION just built."
  echo "         Both claim $BUNDLE_ID, so Launchpad, Spotlight and \`open\` will use the installed one."
  echo "         Run: scripts/release.sh --install"
fi
