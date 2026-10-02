#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
pin=89f7e47d4abbf650c91fae766728af866c5e32a0
source_dir=${1:-}
if [ -z "$source_dir" ]; then
  source_dir=generated/source
  if [ ! -d "$source_dir/.git" ]; then
    git clone https://github.com/Themaister/pyrowave.git "$source_dir"
  fi
  git -C "$source_dir" fetch origin "$pin"
  git -C "$source_dir" checkout --detach "$pin"
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
