APP="/Applications/CrewListr Pro.app"
OUT="$HOME/Desktop/crewlistr-report.txt"
{
  echo "===== macOS ====="
  sw_vers; uname -m
  echo; echo "===== app present? ====="
  ls -ld "$APP" 2>&1
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>&1
  echo; echo "===== quarantine flags ====="
  xattr -r -p com.apple.quarantine "$APP" 2>/dev/null | sort -u | head -5
  echo "(blank above = no quarantine, which is what we want)"
  echo; echo "===== signature ====="
  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -5
  echo; echo "===== gatekeeper ====="
  spctl -a -vvv -t exec "$APP" 2>&1 | head -3
  echo; echo "===== headless launch (no window) ====="
  "$APP/Contents/MacOS/CrewListrProMac" --list 2>&1 | head -25
  echo "exit code: $?"
  echo; echo "===== most recent crash reports ====="
  ls -t "$HOME/Library/Logs/DiagnosticReports"/*.ips 2>/dev/null | head -3
  NEWEST="$(ls -t "$HOME/Library/Logs/DiagnosticReports"/*CrewListr*.ips 2>/dev/null | head -1)"
  if [ -n "$NEWEST" ]; then
    echo "--- $NEWEST ---"
    head -60 "$NEWEST"
  else
    echo "(no CrewListr crash report found)"
  fi
} > "$OUT" 2>&1
echo "Report written to: $OUT"
