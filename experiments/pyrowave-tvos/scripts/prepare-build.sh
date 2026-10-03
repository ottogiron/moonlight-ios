#!/bin/sh
set -eu

repo=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo"

if [ "$#" -ne 0 ]; then
  echo 'Usage: experiments/pyrowave-tvos/scripts/prepare-build.sh' >&2
  exit 2
fi

if ! git diff --ignore-submodules=dirty --quiet HEAD -- \
  .gitmodules X1Kit moonlight-common/moonlight-common-c; then
  echo 'Submodule declarations or gitlinks differ from this checkout; refusing preparation.' >&2
  exit 1
fi

check_submodule() {
  path=$1
  expected=$2
  if [ -e "$path/.git" ]; then
    actual=$(git -C "$path" rev-parse HEAD)
    if [ "$actual" != "$expected" ] || [ "$(git -C "$path" rev-parse --show-toplevel)" != "$repo/$path" ]; then
      echo "Unexpected submodule checkout at $path; expected $expected." >&2
      exit 1
    fi
    if [ "$path" = moonlight-common/moonlight-common-c ]; then
      experiments/pyrowave-tvos/scripts/prepare-common-c.sh --check
    elif [ -n "$(git -C "$path" status --porcelain)" ]; then
      echo "Unexpected submodule changes in $path; refusing preparation." >&2
      exit 1
    fi
  elif [ -d "$path" ] && [ -n "$(ls -A "$path")" ]; then
    echo "Uninitialized submodule path $path contains files; refusing preparation." >&2
    exit 1
  fi
}

check_submodule X1Kit 6e842ae9d5a21916d7c9693c7385d1ac672bc4fa
check_submodule moonlight-common/moonlight-common-c f900dd4767759c7b9d0e93bcea666b55c69ea62f
check_submodule moonlight-common/moonlight-common-c/enet aca87840b57f045a1f7f9299e4b1b9b8e2a5e2f1
check_submodule moonlight-common/moonlight-common-c/nanors b1e3c22ca0cdc0bb83e3cd6ed1a2fc77869ed99a

experiments/pyrowave-tvos/scripts/prepare-dependency.sh
if [ ! -e X1Kit/.git ] ||
   [ ! -e moonlight-common/moonlight-common-c/.git ] ||
   [ ! -e moonlight-common/moonlight-common-c/enet/.git ] ||
   [ ! -e moonlight-common/moonlight-common-c/nanors/.git ]; then
  git submodule update --init --recursive moonlight-common/moonlight-common-c X1Kit
fi
experiments/pyrowave-tvos/scripts/prepare-common-c.sh

echo 'Clean-checkout dependencies prepared for unsigned Moonlight TV builds.'
