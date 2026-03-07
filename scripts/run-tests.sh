#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

XCODE_PROJECT="$PROJECT_DIR/mac/openlyrics.xcodeproj"

xcodebuild -project "$XCODE_PROJECT" -scheme openlyricsTests -destination 'platform=macOS' test
