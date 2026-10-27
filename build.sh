#!/bin/zsh
# Builds NexLauncher.app (with the widget extension), signs it, and optionally installs it.
#   ./build.sh            build into ./NexLauncher.app
#   ./build.sh --install  also copy to /Applications and launch
#   ./build.sh --check-widget  only typecheck the widget extension's sources (fast; used by CI)
# Builds a universal app (Apple silicon + Intel) for macOS 14 and later. ARCHS="arm64" builds one architecture.
set -euo pipefail
cd "$(dirname "$0")"

APP="NexLauncher.app"
ARCHS=(${=ARCHS:-arm64 x86_64})
MIN_MACOS="14.0"

WIDGET="PlugIns/NexWidgets.appex"

# The widget compiles NexCore's sources into its own module, plus the app's illustrations and theme
# (copied without `import NexCore` / `import NexApp`). LoginItem.swift is left out: SMAppService.mainApp isn't
# available to extensions.
widget_sources() {
    CORE=(${(f)"$(ls Sources/NexCore/*.swift | grep -v LoginItem.swift)"})
    SHARED="$(mktemp -d)"
    for f in Sources/NexUI/Illustrations.swift Sources/NexUI/Theme.swift; do
        sed -e '/^import NexCore$/d' -e '/^import NexApp$/d' "$f" > "$SHARED/$(basename $f)"
    done
}

if [[ "${1:-}" == "--check-widget" ]]; then
    widget_sources
    swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macos$MIN_MACOS -application-extension \
        Widgets/NexWidgets.swift $CORE "$SHARED"/*.swift
    echo "Widget sources typecheck."
    exit 0
fi
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)}"
[[ -z "$IDENTITY" ]] && IDENTITY="-" && echo "No signing identity found: using ad-hoc signing (widgets may not load)."
echo "Signing with: $IDENTITY"

echo "==> Building app"
# One build per architecture (a multi-arch `swift build` trips over SwiftTerm's build plugin), joined with lipo.
APP_SLICES=()
for a in $ARCHS; do
    swift build -c release --product NexLauncher --triple $a-apple-macosx$MIN_MACOS
    APP_SLICES+=("$(swift build -c release --triple $a-apple-macosx$MIN_MACOS --show-bin-path)/NexLauncher")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/$(dirname $WIDGET)"
lipo -create $APP_SLICES -output "$APP/Contents/MacOS/NexLauncher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Building widget extension"
EXT="$APP/Contents/$WIDGET"
mkdir -p "$EXT/Contents/MacOS"
widget_sources
SLICES=()
for a in $ARCHS; do
    swiftc -parse-as-library -swift-version 5 -O \
        -target $a-apple-macos$MIN_MACOS -application-extension \
        -Xlinker -e -Xlinker _NSExtensionMain \
        -framework WidgetKit -framework SwiftUI \
        -o "$SHARED/NexWidgets-$a" Widgets/NexWidgets.swift $CORE "$SHARED"/*.swift
    SLICES+=("$SHARED/NexWidgets-$a")
done
lipo -create $SLICES -output "$EXT/Contents/MacOS/NexWidgets"
rm -rf "$SHARED"
cp Widgets/Info.plist "$EXT/Contents/Info.plist"

echo "==> Signing"
codesign --force --sign "$IDENTITY" --entitlements Widgets/NexWidgets.entitlements "$EXT"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP" && echo "Signature OK"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/NexLauncher") (widget: $(lipo -archs "$EXT/Contents/MacOS/NexWidgets")), macOS $MIN_MACOS or later"

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
