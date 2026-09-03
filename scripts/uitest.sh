#!/bin/zsh
# Runs the XCUITest suite: the clicks an in-process test cannot reach.
#
# ── READ THIS BEFORE RUNNING ─────────────────────────────────────────────────
#
# This is not a test run you can work through. XCUITest has no sandbox: it
# synthesises real mouse and keyboard events on the desktop it runs on, seizes
# focus from whatever is in front, and inspects other applications' windows as
# it goes.
#
# On this machine that has quit other running applications — repeatedly and
# reproducibly, including the editor the run was started from, taking the
# session and any unsaved work with it. The failures it reported ("no window
# appeared") were the same instability seen from the inside.
#
# So it asks first, and an automated caller has to say so out loud:
#
#     CREWLISTR_UITEST_CONFIRM=1 ./scripts/uitest.sh
#
# Run it when you have walked away from the Mac, and not before. If you are an
# agent working on this repository: do not set that variable on your own
# initiative. Ask, and let the person decide when their machine is free.
#
# ─────────────────────────────────────────────────────────────────────────────
#
# A Swift package cannot host a UI-testing bundle, so this generates a small
# Xcode project from project.yml, builds the same sources into an app, and
# drives it. `Package.swift` stays the source of truth for shipping — nothing
# here is involved in `swift build -c release` or `scripts/release.sh`.
#
# The generated project is not committed. One project file kept in step by hand
# is one project file that drifts from the package it is supposed to mirror.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${CREWLISTR_UITEST_CONFIRM:-}" != "1" ]]; then
  cat >&2 <<'WARNING'
scripts/uitest.sh drives the real desktop and can quit other running apps.

It synthesises mouse and keyboard events, takes focus, and has been observed
quitting unrelated applications on this machine — including the one it was
launched from. It is not safe to run while you are using the Mac.

When the machine is free:

    CREWLISTR_UITEST_CONFIRM=1 ./scripts/uitest.sh

Everything else — 493 tests, including the in-process interaction tests that
type into the real fields — runs silently under `swift test`.
WARNING
  exit 2
fi

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 2
fi

SQLCIPHER_PREFIX="$(brew --prefix sqlcipher)"
export SQLCIPHER_PREFIX

# Codesign refuses a bundle carrying a resource fork or Finder info, and the
# brand PNGs were written by an image editor that leaves `com.apple.FinderInfo`
# on them. Git does not carry extended attributes, so this only ever bites on a
# machine where the file has been opened by such a tool — which is every machine
# the art is edited on. Stripping is idempotent and changes no file content.
xattr -cr Resources 2>/dev/null || true

xcodegen generate --quiet

# UI tests drive a real window, so this one cannot be silent the way the rest of
# the suite is: the app opens, is clicked, and closes again. It is not part of
# `swift test` for exactly that reason.
# XCUITest synthesises real keyboard and mouse events on the desktop it runs on.
# It activates the app over whatever is in front, and anything that steals focus
# mid-run — a notification, another window coming forward — can land a click
# somewhere unintended. This is not a suite to run while working on the machine.
echo "Running UI tests — an app window will open, take focus, and be clicked."
echo "Leave the machine alone until it finishes."

LOG="${TMPDIR:-/tmp}/crewlistr-uitest.log"

# An app left running by an interrupted run is not replaced by the next one —
# macOS activates the existing instance instead, still holding the old launch
# environment and the old store. Clear it out before starting.
pkill -f "CrewListr Pro UITest.app/Contents/MacOS" 2>/dev/null || true

xcodebuild test \
  -project CrewListrPro.xcodeproj \
  -scheme CrewListrPro \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  "$@" > "$LOG" 2>&1 || true

# The whole log is kept — a UI-test failure is usually explained by the step
# before it, and `tail` on a run this chatty throws exactly that away.
echo
grep -E "Test Case .*(passed|failed)|error:|\*\* TEST" "$LOG" || true
echo
echo "Full log: $LOG"
grep -q "\*\* TEST SUCCEEDED" "$LOG"
