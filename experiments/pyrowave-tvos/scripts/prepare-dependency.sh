#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
if [ "$#" -ne 0 ]; then
  echo 'Usage: scripts/prepare-dependency.sh' >&2
  exit 2
fi

# The manifest records the exact eight blobs reviewed at the private Git pin.
# The small vendored subset is the reproducible source input for clean checkouts.
scripts/verify-dependency.sh --vendor-only

if [ -e generated/pyrowave-metal ] || [ -L generated/pyrowave-metal ]; then
  scripts/verify-dependency.sh
  echo 'Pinned Pyrowave Metal decoder already prepared.'
else
  mkdir -p generated
  cp -R vendor/pyrowave-metal generated/pyrowave-metal
  scripts/verify-dependency.sh
  echo 'Prepared pinned Pyrowave Metal decoder.'
fi
