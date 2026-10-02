#!/usr/bin/env python3
"""Exercise the manifest/layout contract without claiming a GPU decode passed."""
import copy
import hashlib
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
program = root / 'build' / 'pyrowave-mac-verify'
if not program.exists():
    raise SystemExit('Run scripts/build-mac.sh first')

with tempfile.TemporaryDirectory() as tmp:
    directory = pathlib.Path(tmp)
    payload = b'abcdef'
    layout = b'packet_index,offset,size\n0,0,2\n1,2,4\n'
    reference = bytes(1920 * 1080 * 3 // 2)
    files = {'sample.packetized.bin': payload, 'sample.packets.csv': layout,
             'sample.vulkan-reference.yuv': reference}
    for filename, data in files.items():
        (directory / filename).write_bytes(data)
    hashes = {key: hashlib.sha256(value).hexdigest() for key, value in files.items()}
    fixtures = []
    for kind in ('mixed', 'entropy'):
        for rate in (200, 250, 300):
            fixtures.append(dict(name=f'1920x1080_{kind}_{rate}', width=1920, height=1080,
                                 chroma=420, frame_index=5, packet_file='sample.packetized.bin',
                                 packet_layout='sample.packets.csv',
                                 reference_file='sample.vulkan-reference.yuv',
                                 sha256={'packet_file': hashes['sample.packetized.bin'],
                                         'packet_layout': hashes['sample.packets.csv'],
                                         'reference_file': hashes['sample.vulkan-reference.yuv']}))
    manifest = dict(schema_version=1,
                    pyrowave_commit='89f7e47d4abbf650c91fae766728af866c5e32a0',
                    color_space='bt709', color_range='limited', fixtures=fixtures)

    def check(label, data, expect_success, altered_layout=None):
        if altered_layout is not None:
            (directory / 'sample.packets.csv').write_bytes(altered_layout)
            digest = hashlib.sha256(altered_layout).hexdigest()
            for fixture in data['fixtures']:
                fixture['sha256']['packet_layout'] = digest
        (directory / 'manifest.json').write_text(json.dumps(data))
        result = subprocess.run([str(program), '--validate-only', str(directory)],
                                capture_output=True, text=True)
        assert (result.returncode == 0) == expect_success, (label, result.stdout, result.stderr)
        print(f'{label}: PASS')

    check('valid manifest', copy.deepcopy(manifest), True)
    for label, altered in {
        'gap': b'packet_index,offset,size\n0,0,2\n1,3,3\n',
        'overlap': b'packet_index,offset,size\n0,0,3\n1,2,4\n',
        'truncated coverage': b'packet_index,offset,size\n0,0,2\n1,2,3\n',
        'duplicate index': b'packet_index,offset,size\n0,0,2\n0,2,4\n',
        'out of range': b'packet_index,offset,size\n0,0,7\n',
    }.items():
        check(label, copy.deepcopy(manifest), False, altered)
    check('restored valid layout', copy.deepcopy(manifest), True, layout)
    bad = copy.deepcopy(manifest)
    bad['fixtures'][0]['width'] = 1918
    check('wrong dimensions', bad, False)
    bad = copy.deepcopy(manifest)
    bad['fixtures'][0]['sha256']['packet_file'] = '0' * 64
    check('wrong hash', bad, False)
