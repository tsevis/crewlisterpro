#!/bin/bash
#
# Build, test, install and run the iOS app on a simulator.
#
# The Xcode project is generated from `ios-project.yml` and is not committed,
# for the same reason the UI-test project is not: `Package.swift` stays the
# source of truth for the shared code, and a second project file kept in step by
# hand is a second place for the two builds to disagree.
#
#   ./scripts/ios.sh build      compile for the simulator
#   ./scripts/ios.sh test       build and run the iOS test bundle
#   ./scripts/ios.sh run        install and launch on a booted simulator
#   ./scripts/ios.sh shot <f>   screenshot the running app into <f>
#   ./scripts/ios.sh share <f>  put a file into the app's share inbox, as the
#                               share extension would, so the receiving half of
#                               the WhatsApp path can be exercised without one
#   ./scripts/ios.sh device     build for a real device (needs CREWLISTR_TEAM)
#
# CREWLISTR_SIM   the simulator to use          (default: iPhone 17 Pro)
# CREWLISTR_SEED  set to `demo` for `run`       (a fictional fleet, debug only)
# CREWLISTR_TEAM  the Apple Developer team id   (required by `device` only)
set -euo pipefail

cd "$(dirname "$0")/.."

SIMULATOR="${CREWLISTR_SIM:-iPhone 17 Pro}"
PROJECT="CrewListrProiOS.xcodeproj"
SCHEME="CrewListrPro"
BUNDLE_ID="com.tsevis.crewlisterpro.ios"
APP_GROUP="group.com.tsevis.crewlisterpro"
DESTINATION="platform=iOS Simulator,name=$SIMULATOR"

generate() {
    command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }
    # `Version.swift` is the single source of truth for the product identity, on
    # this platform as on the Mac — `release.sh` reads the same two values for
    # the .app's Info.plist. Written down a second time in the spec, they would
    # be a second place to forget.
    CREWLISTR_VERSION="$(version_field short)" \
    CREWLISTR_BUILD="$(version_field build)" \
        xcodegen generate --spec ios-project.yml --project . >/dev/null
}

version_field() {
    sed -n "s/^ *static let $1 = \"\(.*\)\"$/\1/p" Sources/CrewListrProMac/Version.swift | head -1
}

product_path() {
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator \
        -configuration Debug -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/ {d=$2} / FULL_PRODUCT_NAME =/ {n=$2} END {print d "/" n}'
}

boot() {
    # `boot` on an already-booted device is an error rather than a no-op, and it
    # is the common case — so it is allowed to fail.
    xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
    xcrun simctl bootstatus "$SIMULATOR" -b >/dev/null 2>&1 || true
}

case "${1:-build}" in
build)
    generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator \
        -destination "$DESTINATION" -configuration Debug build
    ;;
test)
    generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator \
        -destination "$DESTINATION" -configuration Debug test
    ;;
run)
    generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator \
        -destination "$DESTINATION" -configuration Debug build
    boot
    APP="$(product_path)"
    xcrun simctl install "$SIMULATOR" "$APP"
    # `SIMCTL_CHILD_` is how an environment variable reaches the app rather
    # than `simctl` itself; there is no `--env`.
    SIMCTL_CHILD_CREWLISTR_SEED="${CREWLISTR_SEED:-}" \
        xcrun simctl launch --terminate-running-process "$SIMULATOR" "$BUNDLE_ID"
    ;;
shot)
    boot
    xcrun simctl io "$SIMULATOR" screenshot "${2:-shot.png}"
    ;;
share)
    # Drops a file into the App Group inbox exactly as the share extension
    # would. `simctl` cannot press a button in WhatsApp, and the half of that
    # path this project owns begins at the inbox.
    [ -f "${2:-}" ] || { echo "usage: $0 share <file>" >&2; exit 1; }
    CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR" "$BUNDLE_ID" groups 2>/dev/null \
        | awk -F'\t' -v g="$APP_GROUP" '$1 == g {print $2}')"
    [ -n "$CONTAINER" ] || { echo "the app group container is not there — is the app installed?" >&2; exit 1; }
    mkdir -p "$CONTAINER/Inbox"
    cp "$2" "$CONTAINER/Inbox/$(uuidgen)__$(basename "$2")"
    echo "put $(basename "$2") in the share inbox; bring the app to the front to collect it"
    ;;
device)
    # The simulator does not check who signed the app. A device does, and the
    # App Group is what hands a passport from the extension to the app — see
    # docs/ios.md for the three things the developer account has to have.
    [ -n "${CREWLISTR_TEAM:-}" ] || {
        echo "set CREWLISTR_TEAM to your Apple Developer team id (see docs/ios.md)" >&2
        exit 1
    }
    generate
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphoneos \
        -configuration Debug -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$CREWLISTR_TEAM" CODE_SIGN_STYLE=Automatic \
        CODE_SIGN_IDENTITY="Apple Development" build
    ;;
*)
    echo "usage: $0 [build|test|run|shot <file>|share <file>|device]" >&2
    exit 1
    ;;
esac
