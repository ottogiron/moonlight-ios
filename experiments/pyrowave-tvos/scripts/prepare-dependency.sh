#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
pin=5e4a98f807dddd2498824e3b55ef2fe1845bcc59
source_dir=${1:-}
if [ -z "$source_dir" ]; then
  source_dir=generated/source
  if [ ! -d "$source_dir/.git" ]; then
    echo 'Provide an explicit local checkout of the pinned private Pyrowave source.' >&2
    echo 'For example: scripts/prepare-dependency.sh generated/codec-scan-5e4a98f-source' >&2
    exit 2
  fi
fi
actual=$(git -C "$source_dir" rev-parse HEAD)
if [ "$actual" != "$pin" ]; then
  echo "Pyrowave source is $actual; expected $pin" >&2
  exit 1
fi
mkdir -p generated/pyrowave-metal/shaders
for file in pyrowave_metal.h pyrowave_common.hpp pyrowave_common.mm pyrowave_decoder.mm pyrowave_bitstream.hpp pyrowave_bitstream.cpp; do
  git -C "$source_dir" show "$pin:metal/$file" > "generated/pyrowave-metal/$file"
done
git -C "$source_dir" show "$pin:metal/shaders/pyrowave_msl.h" > generated/pyrowave-metal/shaders/pyrowave_msl.h
git -C "$source_dir" show "$pin:LICENSE" > generated/pyrowave-metal/LICENSE
echo "$pin" > generated/pyrowave-metal/COMMIT
scripts/verify-dependency.sh "$source_dir"
echo 'Prepared pinned Pyrowave Metal decoder.'
