#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ ! -f generated/pyrowave-metal/COMMIT ]; then
  echo 'Run scripts/prepare-dependency.sh first.' >&2
  exit 1
fi
if [ "$(cat generated/pyrowave-metal/COMMIT)" != 5e4a98f807dddd2498824e3b55ef2fe1845bcc59 ]; then
  echo 'Prepared dependency pin is wrong.' >&2
  exit 1
fi
shasum -a 256 -c scripts/pyrowave-metal.sha256
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
