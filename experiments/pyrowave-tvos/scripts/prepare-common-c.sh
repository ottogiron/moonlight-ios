#!/bin/sh
set -eu

repo=$(cd "$(dirname "$0")/../../.." && pwd)
common="$repo/moonlight-common/moonlight-common-c"
patch="$repo/experiments/pyrowave-tvos/patches/common-c-pyrowave.patch"
base=f900dd4767759c7b9d0e93bcea666b55c69ea62f
mode=${1:-prepare}
if [ "$#" -gt 1 ] || { [ "$mode" != prepare ] && [ "$mode" != --check ]; }; then
  echo 'Usage: prepare-common-c.sh [--check]' >&2
  exit 2
fi

if [ ! -e "$common/src/Limelight.h" ] ||
   [ "$(git -C "$common" rev-parse --show-toplevel 2>/dev/null || true)" != "$common" ]; then
  echo "Initialize common-c at $base before applying the tracked patch." >&2
  exit 1
fi
if [ "$(git -C "$common" rev-parse HEAD)" != "$base" ]; then
  echo "common-c is not at the pinned base $base." >&2
  exit 1
fi

if git -C "$common" diff --cached --quiet &&
   [ -z "$(git -C "$common" ls-files --others --exclude-standard)" ] &&
   git -C "$common" diff --binary --unified=0 | cmp -s - "$patch"; then
  echo 'Pinned common-c patch already applied.'
elif [ -z "$(git -C "$common" status --porcelain)" ] &&
     git -C "$common" apply --unidiff-zero --check "$patch"; then
  if [ "$mode" = --check ]; then
    echo 'Pinned common-c base is clean and patch is applicable.'
  else
    git -C "$common" apply --unidiff-zero "$patch"
    echo 'Applied pinned common-c patch.'
  fi
else
  echo 'common-c has unexpected local changes; refusing to overwrite them.' >&2
  exit 1
fi
