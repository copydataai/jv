#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release.sh <version>" >&2
    exit 1
fi

cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree must be clean before release" >&2
    exit 1
fi

if ! grep -Fq "JV_VERSION=\"$VERSION\"" jv.sh; then
    echo "Error: JV_VERSION in jv.sh does not match $VERSION" >&2
    exit 1
fi

tests/run-tests.sh

DIST_ROOT="dist"
RELEASE_DIR="$DIST_ROOT/jv-$VERSION"
ARCHIVE="$DIST_ROOT/jv-$VERSION.tar.gz"

rm -rf "$RELEASE_DIR" "$ARCHIVE"
mkdir -p "$RELEASE_DIR"

cp jv.sh "$RELEASE_DIR/jv"
chmod +x "$RELEASE_DIR/jv"
cp install.sh README.md LICENSE CHANGELOG.md "$RELEASE_DIR/"

if [[ -d completions ]]; then
    cp -R completions "$RELEASE_DIR/completions"
fi

tar -C "$DIST_ROOT" -czf "$ARCHIVE" "jv-$VERSION"

if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$ARCHIVE" > "$DIST_ROOT/checksums.txt"
elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$ARCHIVE" > "$DIST_ROOT/checksums.txt"
else
    echo "Warning: no SHA-256 tool found; skipping checksums" >&2
fi

echo "Built $ARCHIVE"
