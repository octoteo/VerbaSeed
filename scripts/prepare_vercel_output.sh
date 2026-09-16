#!/usr/bin/env bash
set -euo pipefail

WEB_DIR="${1:-apps/learner/build/web}"
OUTPUT_DIR="${2:-.vercel/output}"
CONFIG_FILE="deploy/vercel/config.json"

for required in \
  "$WEB_DIR/index.html" \
  "$WEB_DIR/flutter_bootstrap.js" \
  "$WEB_DIR/sqlite3.wasm" \
  "$CONFIG_FILE"; do
  test -s "$required" || { echo "Missing required Vercel input: $required" >&2; exit 1; }
done

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/static"
cp -a "$WEB_DIR/." "$OUTPUT_DIR/static/"
cp "$CONFIG_FILE" "$OUTPUT_DIR/config.json"

jq -e '.version == 3 and (.routes | type == "array")' "$OUTPUT_DIR/config.json" >/dev/null

echo "Prepared Vercel Build Output from the already-tested Flutter artifact."
