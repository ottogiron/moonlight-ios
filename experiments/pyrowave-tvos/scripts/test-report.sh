#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang++ -std=c++14 -fobjc-arc -Wall -Wextra -Werror -I Core \
  tests/report_stats.mm -framework Foundation -o build/report_stats
build/report_stats
