#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ] || [ ! -f "$1/manifest.json" ]; then
  echo 'Usage: scripts/stage-fixtures.sh /path/to/fixture-directory' >&2
  exit 2
fi
mkdir -p Fixtures
cp "$1"/manifest.json Fixtures/
# Copy only files named by the manifest after the verifier checks it. Paths are
# constrained to plain basenames by the loader, avoiding a recursive copy.
python3 - "$1" <<'PY'
import json, pathlib, shutil, sys
source = pathlib.Path(sys.argv[1])
manifest = json.loads((source / 'manifest.json').read_text())
for fixture in manifest['fixtures']:
    for key in ('packet_file', 'packet_layout', 'reference_file'):
        name = fixture[key]
        if pathlib.Path(name).name != name or name in ('.', '..'):
            raise SystemExit(f'Invalid fixture path: {name}')
        shutil.copyfile(source / name, pathlib.Path('Fixtures') / name)
PY
echo 'Staged fixtures in ignored Fixtures/.'
