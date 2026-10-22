#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_args=(-c release --build-system native --disable-sandbox --scratch-path "${MIO_SWIFT_BUILD_PATH:-$PWD/.build/native}")
swift build "${build_args[@]}"
bin="$(swift build "${build_args[@]}" --show-bin-path)"
app="$PWD/dist/Mio.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MioCompanion" "$app/Contents/MacOS/MioCompanion"
for bundle in "$bin"/*.bundle; do
  [ -d "$bundle" ] && ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done
# Incremental SwiftPM/ditto copies can retain deleted source assets. Replace
# these two owned resource trees so removed motions cannot ship in the app.
resources="$app/Contents/Resources/MioCompanion_MioApp.bundle/Resources"
for name in Mio MioCubism; do
  rm -rf "$resources/$name"
  ditto "$PWD/Sources/MioApp/Resources/$name" "$resources/$name"
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
<key>NSMicrophoneUsageDescription</key><string>在你开启语音后，本机识别唤醒词和对话；可随时停止聆听。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
printf '%s\n' "$app"
