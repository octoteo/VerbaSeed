#!/usr/bin/env bash
set -u

# Vercel treats exit 0 as "ignore this build" and exit 1 as "build it".
# Documentation-only commits should not spend several minutes bootstrapping a
# Flutter toolchain. Runtime, schema, package and build-pipeline changes always
# get a real preview/production build.
BASE_SHA="${VERCEL_GIT_PREVIOUS_SHA:-HEAD^}"

if git diff --quiet "${BASE_SHA}" HEAD -- \
  apps/learner \
  packages \
  schemas \
  scripts \
  vercel.json; then
  echo "No deployable VerbaSeed changes detected; skipping Vercel build."
  exit 0
fi

echo "Deployable VerbaSeed changes detected; running Vercel build."
exit 1
