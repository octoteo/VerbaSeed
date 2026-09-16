#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.47.4"
FLUTTER_HOME="${HOME}/.cache/verbaseed/flutter-${FLUTTER_VERSION}"

if [[ ! -x "${FLUTTER_HOME}/bin/flutter" ]]; then
  mkdir -p "$(dirname "${FLUTTER_HOME}")"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}"
fi

export PATH="${FLUTTER_HOME}/bin:${PATH}"
flutter --version
flutter config --enable-web

bash scripts/prepare_local_store.sh

pushd apps/learner >/dev/null
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build web --release
popd >/dev/null
