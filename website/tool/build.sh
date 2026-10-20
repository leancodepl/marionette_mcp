#!/usr/bin/env bash
# Builds the static site into build/jaspr. Used by tool/netlify_build.sh on
# Netlify and by anyone building locally; expects `dart` and `jaspr` on PATH.
#
# SITE_URL is the URL the build will be served from. It drives <base href>,
# canonical and Open Graph URLs, the sitemap, and robots.txt: anything other
# than the production domain is treated as a preview and kept out of search
# engines.
set -euo pipefail

PRODUCTION_URL="https://marionette.leancode.co"
SITE_URL="${SITE_URL:-$PRODUCTION_URL}"
SITE_URL="${SITE_URL%/}"
echo "Building for $SITE_URL"

if command -v jaspr >/dev/null 2>&1; then
  jaspr="jaspr"
else
  # The pub cache's bin directory is not always on PATH.
  jaspr="dart pub global run jaspr_cli:jaspr"
fi
$jaspr build --sitemap-domain "$SITE_URL" --dart-define=SITE_URL="$SITE_URL"

# Ship only the rendered page and its assets, not build_runner's intermediate
# package sources.
rm -rf build/jaspr/packages build/jaspr/.dart_tool build/jaspr/.build.manifest

if [ "$SITE_URL" != "$PRODUCTION_URL" ]; then
  printf 'User-agent: *\nDisallow: /\n' > build/jaspr/robots.txt
fi

ls -la build/jaspr
