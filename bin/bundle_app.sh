#!/bin/sh
# Bundles this project's built binary into a macOS .app via app_bundler
# (https://github.com/jockofcode/app_bundler, a sibling project in this
# workspace). Produces build/Vector Blaster.app, ad-hoc signed so it launches
# without a Gatekeeper prompt.
#
# Usage: bin/bundle_app.sh [OUTPUT_DIR]   (default OUTPUT_DIR: build)
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
WORKSPACE_DIR=$(cd "$PROJECT_DIR/.." && pwd)
OUTPUT_DIR="${1:-$PROJECT_DIR/build}"

APP_BUNDLER="$WORKSPACE_DIR/app_bundler/build/bin/app_bundler"
if [ ! -x "$APP_BUNDLER" ]; then
  if command -v app_bundler >/dev/null 2>&1; then
    APP_BUNDLER="$(command -v app_bundler)"
  else
    echo "bundle_app.sh: app_bundler not built -- run: (cd $WORKSPACE_DIR/app_bundler && spin build)" >&2
    exit 1
  fi
fi

cd "$PROJECT_DIR"
spin build vector_blaster

"$APP_BUNDLER" \
  --executable="$PROJECT_DIR/build/bin/vector_blaster" \
  --name="Vector Blaster" \
  --identifier=com.example.vector_blaster \
  --icon="$PROJECT_DIR/assets/icons/icon.icns" \
  --output="$OUTPUT_DIR" \
  --sign=- \
  --force
