#!/usr/bin/env bash
# Netlify's ignore command (see netlify.toml): exit 0 skips the build, exit 1
# runs it. Builds only when the site or the package version it shows changed,
# and builds whenever that cannot be told, e.g. on the first build after the
# project was linked to this repository, or on a retry without cache.

if [ -z "${CACHED_COMMIT_REF:-}" ] ||
  [ "$CACHED_COMMIT_REF" = "$COMMIT_REF" ] ||
  ! git cat-file -e "$CACHED_COMMIT_REF^{commit}" 2>/dev/null; then
  exit 1
fi

if git diff --quiet "$CACHED_COMMIT_REF" "$COMMIT_REF" -- . \
  ../packages/marionette_mcp/pubspec.yaml; then
  exit 0
fi
exit 1
