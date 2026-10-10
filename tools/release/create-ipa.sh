#!/bin/sh

set -eu

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"

BUILD_TYPE="${1:-normal}"
case "$BUILD_TYPE" in
	--trollstore)
		OUTPUT_NAME="Reynard-TrollStore.tipa"
		PTRACE_JIT_NAME="ts_ptrace_jit"
		;;
	--jailbroken)
		OUTPUT_NAME="Reynard-Jailbroken.ipa"
		PTRACE_JIT_NAME="jb_ptrace_jit"
		;;
	*)
		BUILD_TYPE="normal"
		OUTPUT_NAME="Reynard.ipa"
		;;
esac

cd "$ROOT_DIR"

if [ ! -d "$APP_DIR" ]; then
	echo "Missing archive output at $APP_DIR"
	echo "Run tools/release/build-app.sh first."
	exit 1
fi

APP_PATH="$(find "$APP_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
	echo "No .app found in $APP_DIR"
	exit 1
fi

# I absolutely hate Apple for this
# Why is my bundle identifier just become unavailable for no reason?
plutil -replace CFBundleIdentifier -string "com.malaoshi.Reynard" "$APP_PATH/Info.plist"

# The helper extension is renamed together with the app, so its bundle ends up
# being called "马老师专属 Helper.appex" instead of "Reynard Helper.appex".
# Discover the extension bundles dynamically rather than hardcoding product names.
HELPER_APPEX=""
for APPEX in "$APP_PATH"/PlugIns/*.appex; do
	[ -d "$APPEX" ] || continue
	APPEX_NAME="$(basename "$APPEX" .appex)"
	case "$APPEX_NAME" in
		*Helper*)
			HELPER_APPEX="$APPEX"
			plutil -replace CFBundleIdentifier -string "com.malaoshi.Reynard.Helper" "$APPEX/Info.plist"
			;;
		*OpenIn*)
			plutil -replace CFBundleIdentifier -string "com.malaoshi.Reynard.OpenIn" "$APPEX/Info.plist"
			;;
		*)
			echo "Unexpected app extension bundle: $APPEX_NAME" >&2
			exit 1
			;;
	esac
done

if [ -z "$HELPER_APPEX" ]; then
	echo "Helper app extension not found in $APP_PATH/PlugIns"
	exit 1
fi

HELPER_APPEX_NAME="$(basename "$HELPER_APPEX" .appex)"

rm -rf "$WORK_DIR" "$ROOT_DIR/dist/$OUTPUT_NAME"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"

if [ "$BUILD_TYPE" != "normal" ]; then
	APP_BUNDLE="Payload/$(basename "$APP_PATH")"
	HELPER_BUNDLE="$APP_BUNDLE/PlugIns/$HELPER_APPEX_NAME"
	PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c"
	PTRACE_JIT_OUT="$APP_BUNDLE/$PTRACE_JIT_NAME"

	"$CLANG_PATH" \
		-arch arm64 \
		-isysroot "$SDK_PATH" \
		-miphoneos-version-min=13.0 \
		-Os \
		"$PTRACE_JIT_SRC" \
		-o "$PTRACE_JIT_OUT"

	chmod 0755 "$PTRACE_JIT_OUT"

	# Resolve the real executable paths from each bundle's Info.plist instead of
	# assuming they match the bundle name. Renaming the product changes the bundle
	# name and the executable name independently, so hardcoded paths such as
	# "Payload/Reynard.app/Reynard" silently break once the app gets rebranded.
	MAIN_BIN_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Info.plist" 2>/dev/null || true)"
	HELPER_BIN_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$HELPER_BUNDLE/Info.plist" 2>/dev/null || true)"
	MAIN_BIN="$APP_BUNDLE/$MAIN_BIN_NAME"
	HELPER_BIN="$HELPER_BUNDLE/$HELPER_BIN_NAME"

	echo "Signing binaries:"
	echo "  jit    -> $PTRACE_JIT_OUT"
	echo "  main   -> $MAIN_BIN"
	echo "  helper -> $HELPER_BIN"

	for BIN in "$PTRACE_JIT_OUT" "$MAIN_BIN" "$HELPER_BIN"; do
		if [ ! -f "$BIN" ]; then
			echo "Failed to locate binary: $BIN" >&2
			echo "--- $APP_BUNDLE ---" >&2
			ls -la "$APP_BUNDLE" >&2 || true
			echo "--- $APP_BUNDLE/PlugIns ---" >&2
			ls -la "$APP_BUNDLE/PlugIns" >&2 || true
			echo "--- $HELPER_BUNDLE ---" >&2
			ls -la "$HELPER_BUNDLE" >&2 || true
			exit 1
		fi
	done

	ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
	ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "$MAIN_BIN"
	ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "$HELPER_BIN"
fi

if [ "$BUILD_TYPE" = "--jailbroken" ]; then
	# Since releases are now built on GitHub Actions, and it does not have proper signing yet (i believe it
	# requires a paid Apple developer account because of using the free one we would have to replace the
	# provisioning profile once every 7 days?). So this is a workaround for the issue where libhooker-based
	# jailbreaks just refuse to load the adhoc signed dylib and cause the app to crash.
	curl --location --output "Reynard-0.10.0.ipa" "https://github.com/minh-ton/reynard-browser/releases/download/0.10.0/Reynard.ipa" # 0.10.0 is the last one that is properly signed
	unzip -p "Reynard-0.10.0.ipa" "Payload/Reynard.app/Frameworks/libswift_Concurrency.dylib" > "Payload/Reynard.app/Frameworks/libswift_Concurrency.dylib"
fi

zip -r "../$OUTPUT_NAME" Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
