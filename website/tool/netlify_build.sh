#!/usr/bin/env bash
# Netlify's build command (see netlify.toml). Netlify's build image has no
# Dart, so this installs a pinned SDK and the Jaspr CLI, then builds with
# tool/build.sh. Production builds for marionette.leancode.co; Deploy Previews
# and branch deploys build for their own URL, which tool/build.sh keeps out of
# search engines.
set -euo pipefail

# Bump both together: the checksum is the one the Dart archive publishes next
# to the zip, as `<zip>.sha256sum`.
DART_VERSION="3.13.5"
DART_SHA256="ea864bc64df30a6b8bdf30b2e32550f7717d9a890de8f40293aeabb924fe232b"
JASPR_CLI_VERSION="0.23.4"

sdk_dir="$HOME/dart-sdk-$DART_VERSION"
if [ ! -x "$sdk_dir/dart-sdk/bin/dart" ]; then
  zip="$(mktemp)"
  curl -fsSL -o "$zip" "https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/dartsdk-linux-x64-release.zip"
  echo "$DART_SHA256  $zip" | sha256sum --check --quiet
  mkdir -p "$sdk_dir"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip" -d "$sdk_dir"
  else
    # Python's zipfile drops file modes, so restore them by hand.
    python3 - "$zip" "$sdk_dir" <<'EOF'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    for info in archive.infolist():
        path = archive.extract(info, sys.argv[2])
        if mode := info.external_attr >> 16:
            os.chmod(path, mode)
EOF
  fi
  rm "$zip"
fi
export PATH="$sdk_dir/dart-sdk/bin:$HOME/.pub-cache/bin:$PATH"
dart --version

dart pub global activate jaspr_cli "$JASPR_CLI_VERSION"
dart pub get

if [ "${CONTEXT:-}" = "production" ]; then
  unset SITE_URL
else
  export SITE_URL="$DEPLOY_PRIME_URL"
fi
bash tool/build.sh
