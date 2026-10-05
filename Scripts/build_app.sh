#!/bin/zsh
# Builds TradeSync.app (universal: Apple Silicon + Intel), installs it to
# ~/Applications, and packages a shareable zip in build/.
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP_NAME="TradeSync"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

# Command Line Tools 27 ship a SwiftUI whose @State needs a compiler plugin
# that only full Xcode includes. Build against the macOS 26 SDK when present.
if [ -z "$SDKROOT" ]; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
             /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
    if [ -d "$sdk" ]; then export SDKROOT="$sdk"; break; fi
  done
fi
[ -n "$SDKROOT" ] && echo "▸ Using SDK: $SDKROOT"

# Each architecture is copied aside as soon as it's built: newer toolchains
# write every arch to the same output path, so the next build would overwrite it.
SLICES="$BUILD_DIR/slices"
rm -rf "$SLICES" && mkdir -p "$SLICES"

echo "▸ Compiling (release, arm64)…"
swift build -c release --arch arm64
cp "$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME" "$SLICES/$APP_NAME-arm64"
ARM="$SLICES/$APP_NAME-arm64"

echo "▸ Compiling (release, x86_64)…"
if swift build -c release --arch x86_64 >/dev/null 2>&1; then
  cp "$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME" "$SLICES/$APP_NAME-x86_64"
  X86="$SLICES/$APP_NAME-x86_64"
else
  echo "  (Intel slice unavailable — shipping Apple Silicon only)"
  X86=""
fi

# Guard against both slices being the same arch.
if [ -n "$X86" ] && [ "$(lipo -archs "$X86")" = "$(lipo -archs "$ARM")" ]; then
  echo "  (Intel build produced $(lipo -archs "$X86") — shipping Apple Silicon only)"
  X86=""
fi

echo "▸ Generating icon…"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ -n "$X86" ]; then
  lipo -create "$ARM" "$X86" -output "$APP/Contents/MacOS/$APP_NAME"
else
  cp "$ARM" "$APP/Contents/MacOS/$APP_NAME"
fi
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TradeSync</string>
    <key>CFBundleDisplayName</key><string>TradeSync</string>
    <key>CFBundleIdentifier</key><string>com.tradesync.journal</string>
    <key>CFBundleVersion</key><string>1.1</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleExecutable</key><string>TradeSync</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
    <key>NSHumanReadableCopyright</key><string>Built with TradeSync</string>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)…"
codesign --force --deep -s - "$APP"
echo "   architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"

echo "▸ Installing to ~/Applications…"
mkdir -p ~/Applications
rm -rf ~/Applications/$APP_NAME.app
cp -R "$APP" ~/Applications/

echo "▸ Packaging shareable zip…"
# One file to send: the app plus install instructions, in a TradeSync folder.
SHARE="$BUILD_DIR/share"
rm -rf "$SHARE" "$BUILD_DIR/$APP_NAME-Share.zip" "$BUILD_DIR/$APP_NAME.zip" "$BUILD_DIR/INSTALL.txt"
mkdir -p "$SHARE/$APP_NAME"
ditto "$APP" "$SHARE/$APP_NAME/$APP_NAME.app"
cp "$ROOT/Scripts/INSTALL.txt" "$SHARE/$APP_NAME/How to Install $APP_NAME.txt"
(cd "$SHARE" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "../$APP_NAME-Share.zip")

echo "✓ Installed: ~/Applications/$APP_NAME.app"
echo "✓ Shareable: $BUILD_DIR/$APP_NAME-Share.zip"
