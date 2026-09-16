#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE_DIR="${ROOT_DIR}/packages/local_store"
WEB_DIR="${ROOT_DIR}/apps/learner/web"

pushd "${STORE_DIR}" >/dev/null
flutter pub get
dart run build_runner build --delete-conflicting-outputs

SQLITE_VERSION="$(awk '/^  sqlite3:/{found=1} found && /version:/{gsub(/\"/, \"\", $2); print $2; exit}' pubspec.lock)"
if [[ -z "${SQLITE_VERSION}" ]]; then
  echo "Unable to resolve sqlite3 package version" >&2
  exit 1
fi

curl --fail --location --retry 3 --silent --show-error \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE_VERSION}/sqlite3.wasm" \
  --output "${WEB_DIR}/sqlite3.wasm"

dart compile js -O4 \
  --output "${WEB_DIR}/drift_worker.dart.js" \
  tool/drift_worker.dart
rm -f "${WEB_DIR}/drift_worker.dart.js.deps" "${WEB_DIR}/drift_worker.dart.js.map"
popd >/dev/null
