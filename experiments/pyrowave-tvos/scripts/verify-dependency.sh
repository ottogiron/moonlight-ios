#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
source_dir=${1:-generated/source}
pin=89f7e47d4abbf650c91fae766728af866c5e32a0
if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$pin" ]; then
  echo 'Pyrowave source checkout is not at the pinned commit.' >&2
  exit 1
fi
for file in pyrowave_metal.h pyrowave_common.hpp pyrowave_common.mm pyrowave_decoder.mm pyrowave_bitstream.hpp pyrowave_bitstream.cpp; do
  git -C "$source_dir" show "$pin:metal/$file" | cmp - "generated/pyrowave-metal/$file"
done
git -C "$source_dir" show "$pin:metal/shaders/pyrowave_msl.h" | cmp - generated/pyrowave-metal/shaders/pyrowave_msl.h
git -C "$source_dir" show "$pin:LICENSE" | cmp - generated/pyrowave-metal/LICENSE
shasum -a 256 -c scripts/pyrowave-metal.sha256
echo 'Pinned Pyrowave decoder subset and MIT license: byte-for-byte verified.'
