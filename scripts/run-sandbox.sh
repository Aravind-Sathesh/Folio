#!/bin/zsh
# Builds Folio and runs it against a throwaway copy of the sample files. Your real Downloads and Documents are never touched.
# Usage: scripts/run-sandbox.sh [sandbox-folder]   (default ~/FolioSandbox, recreated every run)
set -e
cd "$(dirname "$0")/.."
ROOT="${1:-$HOME/FolioSandbox}"
pkill -x Folio 2>/dev/null || true

xcodebuild -project Folio.xcodeproj -scheme Folio -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"

rm -rf "$ROOT"
mkdir -p "$ROOT/Downloads" "$ROOT/Documents/Misc" "$ROOT/Support"
cp -R Tests/Fixtures/documents-tree/. "$ROOT/Documents/"
# Documents starts messy, for Restructure: the whole corpus and the markdown edge cases dumped in one folder.
cp Tests/Fixtures/corpus/* "$ROOT/Documents/Misc/"
mkdir -p "$ROOT/Documents/Misc/md-samples" && cp -R Tests/Fixtures/md-samples/. "$ROOT/Documents/Misc/md-samples/"
echo "Sandbox: $ROOT"
echo "Folio is starting. Finish setup in the welcome window. Click the tray icon any time to open Folio. Then:"
echo "  Autonomous: copy files into $ROOT/Downloads (they're filed after 60 s)"
echo "  Restructure: Folio window > Restructure > pick a folder"
open -n build/Build/Products/Debug/Folio.app --args -FolioRoot "$ROOT"
