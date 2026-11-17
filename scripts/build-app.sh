#!/bin/bash
# Builds dist/Zest.app (Apple Silicon) and dist/Zest.zip.
#
# Signing: set ZEST_SIGN_IDENTITY to a code signing identity (its name or SHA-1),
# and ZEST_KEYCHAIN if it lives in a separate keychain. Without it the app is signed
# ad hoc, which works locally but macOS forgets the Accessibility permission after
# every rebuild. See docs/releasing.md.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
version=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/ZestCore/Version.swift)
# Use the local signing keychain from scripts/setup-local-signing.sh when present.
if [ -z "${ZEST_SIGN_IDENTITY:-}" ] && [ -f "$HOME/.zest-signing/identity" ] && [ -f "$HOME/.zest-signing/zest.keychain-db" ]; then
  ZEST_SIGN_IDENTITY=$(cat "$HOME/.zest-signing/identity")
  ZEST_KEYCHAIN="$HOME/.zest-signing/zest.keychain-db"
  security unlock-keychain -p "$(cat "$HOME/.zest-signing/keychain-password")" "$ZEST_KEYCHAIN"
fi
identity=${ZEST_SIGN_IDENTITY:--}
dist="$root/dist"
app="$dist/Zest.app"

echo "Building zest $version"
swift build -c release --arch arm64 --product ZestApp
swift build -c release --arch arm64 --product zest
bin=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$bin/ZestApp" "$app/Contents/MacOS/Zest"
cp "$bin/zest" "$app/Contents/Helpers/zest"

"$bin/zest" build-specs --from specs --to "$app/Contents/Resources/specs"
cp shell/zest.zsh "$app/Contents/Resources/zest.zsh"
cp -R assets/icons "$app/Contents/Resources/icons"
cp -R themes "$app/Contents/Resources/themes"
[ -f assets/AppIcon.icns ] && cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.rostik32.zest</string>
  <key>CFBundleName</key><string>zest</string>
  <key>CFBundleDisplayName</key><string>zest</string>
  <key>CFBundleExecutable</key><string>Zest</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

sign=(codesign --force --sign "$identity" --timestamp=none)
[ -n "${ZEST_KEYCHAIN:-}" ] && sign+=(--keychain "$ZEST_KEYCHAIN")
"${sign[@]}" --identifier io.github.rostik32.zest.cli "$app/Contents/Helpers/zest"
"${sign[@]}" "$app"
codesign --verify --deep --strict "$app"

(cd "$dist" && rm -f Zest.zip && ditto -c -k --keepParent Zest.app Zest.zip && shasum -a 256 Zest.zip > Zest.zip.sha256)
echo "Built $app ($(du -sh "$app" | cut -f1)), zip $(du -h "$dist/Zest.zip" | cut -f1)"
