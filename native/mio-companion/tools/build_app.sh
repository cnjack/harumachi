#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
bin="$(swift build -c release --show-bin-path)"
app="$PWD/dist/Mio.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MioCompanion" "$app/Contents/MacOS/MioCompanion"
for bundle in "$bin"/*.bundle; do
  [ -d "$bundle" ] && ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.harumachi.MioCompanion</string>
<key>CFBundleName</key><string>澪</string>
<key>CFBundleDisplayName</key><string>澪 · 晴町桌面来信</string>
<key>CFBundleExecutable</key><string>MioCompanion</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
printf '%s\n' "$app"
