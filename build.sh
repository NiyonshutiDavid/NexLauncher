#!/bin/zsh
# Builds NexLauncher.app (with the widget extension), signs it, and optionally installs it.
#   ./build.sh            build into ./NexLauncher.app
#   ./build.sh --install  also copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

APP="NexLauncher.app"
WIDGET="PlugIns/NexWidgets.appex"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)}"
[[ -z "$IDENTITY" ]] && IDENTITY="-" && echo "No signing identity found: using ad-hoc signing (widgets may not load)."
echo "Signing with: $IDENTITY"

echo "==> Building app"
swift build -c release --product NexLauncher
BIN="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/$(dirname $WIDGET)"
cp "$BIN/NexLauncher" "$APP/Contents/MacOS/NexLauncher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Building widget extension"
EXT="$APP/Contents/$WIDGET"
mkdir -p "$EXT/Contents/MacOS"
# LoginItem.swift is excluded: SMAppService.mainApp isn't available to extensions.
CORE=(${(f)"$(ls Sources/NexCore/*.swift | grep -v LoginItem.swift)"})
# The widget also draws the app's illustrations and theme: copy them without `import NexCore`
# (the widget compiles NexCore's sources into its own module).
SHARED="$(mktemp -d)"
for f in Sources/NexUI/Illustrations.swift Sources/NexUI/Theme.swift; do
    sed '/^import NexCore$/d' "$f" > "$SHARED/$(basename $f)"
done
swiftc -parse-as-library -swift-version 5 -O \
    -target arm64-apple-macos26.0 -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -framework WidgetKit -framework SwiftUI \
    -o "$EXT/Contents/MacOS/NexWidgets" Widgets/NexWidgets.swift $CORE "$SHARED"/*.swift
rm -rf "$SHARED"
cp Widgets/Info.plist "$EXT/Contents/Info.plist"

echo "==> Signing"
codesign --force --sign "$IDENTITY" --entitlements Widgets/NexWidgets.entitlements "$EXT"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "Signature OK"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    # Don't kill a running copy that has services, agents or terminals under it (they'd be cut off).
    if PID=$(pgrep -x NexLauncher); then
        if [[ -n "$(pgrep -P $PID)" && "${FORCE:-0}" != "1" ]]; then
            echo "NexLauncher has running services, agents or terminal tabs. Quit it first (or FORCE=1 ./build.sh --install)." >&2
            exit 1
        fi
        osascript -e 'tell application "NexLauncher" to quit' >/dev/null 2>&1 || true
        sleep 2
        pkill -x NexLauncher 2>/dev/null || true
    fi
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/$APP"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP"
    open "/Applications/$APP"
    echo "Installed and launched."
fi
