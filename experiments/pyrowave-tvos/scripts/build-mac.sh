#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ ! -f generated/pyrowave-metal/COMMIT ]; then
  echo 'Run scripts/prepare-dependency.sh first.' >&2
  exit 1
fi
if [ "$(cat generated/pyrowave-metal/COMMIT)" != 89f7e47d4abbf650c91fae766728af866c5e32a0 ]; then
  echo 'Prepared dependency pin is wrong.' >&2
  exit 1
fi
mkdir -p build
xcrun clang++ -std=c++14 -fobjc-arc -Wall -Wextra -O2 \
  -mmacosx-version-min=13.0 -I Core -I generated/pyrowave-metal \
  -x objective-c++ Core/PWProbeCore.mm MacCLI/main.mm \
  generated/pyrowave-metal/pyrowave_common.mm \
  generated/pyrowave-metal/pyrowave_decoder.mm \
  -x c++ generated/pyrowave-metal/pyrowave_bitstream.cpp \
  -framework Foundation -framework Metal -framework QuartzCore \
  -framework IOSurface \
  -o build/pyrowave-mac-verify
