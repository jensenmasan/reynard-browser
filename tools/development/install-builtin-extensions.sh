#!/bin/sh

# Copies the add-ons bundled with the browser into the Gecko app directory so
# they can be installed as built-in extensions through
# resource://app/extensions/<name>/.
#
# Must run after tools/development/apply-patches.sh and before the Gecko build.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$ROOT_DIR/engine/firefox/mobile/ios/app"
SOURCE_ROOT="$ROOT_DIR/extensions"

if [ ! -d "$APP_DIR" ]; then
	echo "Missing Gecko app source directory: $APP_DIR" >&2
	echo "Run tools/development/update-gecko.sh first." >&2
	exit 1
fi

install_extension() {
	NAME="$1"
	SOURCE="$SOURCE_ROOT/$NAME"
	DESTINATION="$APP_DIR/extensions/$NAME"

	if [ ! -d "$SOURCE" ]; then
		echo "Missing extension directory: $SOURCE" >&2
		exit 1
	fi

	rm -rf "$DESTINATION"
	mkdir -p "$DESTINATION"
	cp "$SOURCE"/*.js "$SOURCE"/*.json "$SOURCE"/*.svg "$DESTINATION"/

	# Package the files with moz.build so they end up next to the other
	# resource://app/extensions/... folders.
	MARKER="extensions/$NAME"
	if ! grep -q "$MARKER" "$APP_DIR/moz.build"; then
		{
			echo ""
			echo "FINAL_TARGET_FILES.extensions.$NAME += ["
			for FILE in "$DESTINATION"/*; do
				BASENAME="$(basename "$FILE")"
				echo "    \"extensions/$NAME/$BASENAME\","
			done
			echo "]"
		} >> "$APP_DIR/moz.build"
	fi

	echo "Installed built-in extension: $NAME"
}

install_extension "malaoshi_translate"
