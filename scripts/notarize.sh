#!/bin/zsh
# Submits the disk image to Apple's notary service and staples the ticket.
#
# usage: notarize.sh <dmg> [keychain profile]
#
# Notarization is the only thing that lets someone else open the app by
# double-clicking it. It needs three things this repository cannot hold: a paid
# Developer Program membership, a Developer ID Application certificate in the
# keychain, and credentials for notarytool. Store the credentials once:
#
#   xcrun notarytool store-credentials CrewListrPro \
#     --apple-id <apple-id> \
#     --team-id <team-id> \
#     --password <app-specific-password>
#
# The password is an app-specific password from appleid.apple.com, not the
# Apple ID password. notarytool puts it in the keychain; it is never read from
# this repository or from the environment.
#
# Then build with: scripts/release.sh --notarize
set -euo pipefail

DMG="$1"
PROFILE="${2:-CrewListrPro}"

if [[ ! -f "$DMG" ]]; then
  echo "No such disk image: $DMG" >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "No notarytool credentials stored under the profile '$PROFILE'." >&2
  echo "Create them once with:" >&2
  echo "  xcrun notarytool store-credentials $PROFILE \\" >&2
  echo "    --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>" >&2
  exit 1
fi

# --wait blocks until Apple answers, usually a few minutes. A rejection comes
# back with a submission id; `notarytool log <id>` then names the binary and
# the reason, which is almost always a missing hardened runtime or an unsigned
# nested executable.
echo "Submitting $(basename "$DMG") to Apple. This usually takes a few minutes."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

# Stapling writes the ticket into the image itself, so the recipient's Mac can
# verify it without asking Apple — which matters for an app whose whole premise
# is working offline, and on a boat.
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Stapled. $(basename "$DMG") now opens on any Mac with no extra steps."
