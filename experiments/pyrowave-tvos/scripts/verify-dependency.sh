#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
case "${1:-}" in
  '') [ "$#" -eq 0 ] || exit 2; directories='vendor/pyrowave-metal generated/pyrowave-metal' ;;
  --vendor-only) [ "$#" -eq 1 ] || exit 2; directories='vendor/pyrowave-metal' ;;
  *) echo 'Usage: scripts/verify-dependency.sh [--vendor-only]' >&2; exit 2 ;;
esac

pin=5e4a98f807dddd2498824e3b55ef2fe1845bcc59
files='COMMIT
LICENSE
pyrowave_bitstream.cpp
pyrowave_bitstream.hpp
pyrowave_common.hpp
pyrowave_common.mm
pyrowave_decoder.mm
pyrowave_metal.h
shaders/pyrowave_msl.h'

for directory in $directories; do
  if [ ! -d "$directory" ] || [ -L "$directory" ]; then
    echo "Missing or unsafe Pyrowave decoder directory: $directory" >&2
    exit 1
  fi
  actual=$(find "$directory" ! -type d | sed "s|^$directory/||" | LC_ALL=C sort)
  directories_found=$(find "$directory" -type d | LC_ALL=C sort)
  if [ "$actual" != "$files" ] ||
     [ "$directories_found" != "$(printf '%s\n%s/shaders' "$directory" "$directory")" ] ||
     [ -n "$(find "$directory" -type l -print)" ]; then
    echo "Unexpected Pyrowave decoder files in $directory" >&2
    exit 1
  fi
  if ! printf '%s\n' "$pin" | cmp -s - "$directory/COMMIT"; then
    echo "Pyrowave decoder pin mismatch in $directory" >&2
    exit 1
  fi
done

sed 's|generated/pyrowave-metal/|vendor/pyrowave-metal/|' \
  scripts/pyrowave-metal.sha256 | shasum -a 256 -c -
if [ "$#" -eq 0 ]; then
  shasum -a 256 -c scripts/pyrowave-metal.sha256
fi
echo 'Pyrowave Metal subset, pin and MIT license verified.'
