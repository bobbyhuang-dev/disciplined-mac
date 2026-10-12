#!/bin/bash
# Runs every test: the browser extension's (Node) and the app's (Swift Testing, via Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

node --test Tests/Extension/*.test.mjs
# Only the summary and failures; xcodebuild's own exit status decides the result.
xcodebuild -project Disciplined.xcodeproj -scheme Disciplined -derivedDataPath build test 2>&1 |
  { grep -E "error:|✘|Test run with|\*\* (BUILD|TEST) FAILED" || true; }
