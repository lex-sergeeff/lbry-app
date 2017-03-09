#!/bin/bash

set -euo pipefail
set -x

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$ROOT"

if [ "$(uname)" == "Darwin" ]; then
    ICON="$ROOT/build/icon.icns"
else
    ICON="$ROOT/build/icons/lbry48.png"
fi

FULL_BUILD="${FULL_BUILD:-false}"
if [ -n "${TEAMCITY_VERSION:-}" -o -n "${APPVEYOR:-}" ]; then
  FULL_BUILD="true"
fi

if [ "$FULL_BUILD" == "true" ]; then
  # install dependencies
  $ROOT/prebuild.sh

  VENV="$ROOT/build_venv"
  if [ -d "$VENV" ]; then
    rm -rf "$VENV"
  fi
  virtualenv "$VENV"
  set +u
  source "$VENV/bin/activate"
  set -u
  pip install -r "$ROOT/requirements.txt"
  python "$ROOT/set_version.py"
  python "$ROOT/set_build.py"
fi

[ -d "$ROOT/dist" ] && rm -rf "$ROOT/dist"
mkdir -p "$ROOT/dist"
[ -d "$ROOT/app/dist" ] && rm -rf "$ROOT/app/dist"
mkdir -p "$ROOT/app/dist"

npm install



############
#    UI    #
############

(
  cd "$ROOT/ui"
  npm install
  node_modules/.bin/node-sass --output dist/css --sourcemap=none scss/
  node_modules/.bin/webpack
  cp -r dist/* "$ROOT/app/dist/"
)



####################
#  lbrynet-daemon  #
####################

(
  cd "$ROOT/lbrynet-daemon"
  pip install -r linux_macos.txt
  pyinstaller -y lbry.onefile.spec
  mv dist/lbrynet-daemon "$ROOT/app/dist/"
)
python zip_daemon.py


###################
#  Build the app  #
###################

(
  cd "$ROOT/app"
  npm install
)

if [ "$FULL_BUILD" == "true" ]; then
  if [ "$(uname)" == "Darwin" ]; then
    security unlock-keychain -p ${KEYCHAIN_PASSWORD} osx-build.keychain
  fi

  node_modules/.bin/build -p never

  # electron-build has a publish feature, but I had a hard time getting
  # it to reliably work and it also seemed difficult to configure. Not proud of
  # this, but it seemed better to write my own.
  python release_on_tag.py

  deactivate

  echo 'Build and packaging complete.'
else
  echo 'Build complete. Run `./node_modules/.bin/electron app` to launch the app'
fi