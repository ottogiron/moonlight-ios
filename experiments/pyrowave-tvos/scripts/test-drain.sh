#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang++ -std=c++14 -Wall -Wextra -Werror -I Core tests/drain_tracker.cpp -o build/drain_tracker
build/drain_tracker
