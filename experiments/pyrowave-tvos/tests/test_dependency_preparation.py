#!/usr/bin/env python3
"""Check the clean-checkout decoder recipe without an old source checkout."""

import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DependencyPreparationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name) / 'experiments' / 'pyrowave-tvos'
        (self.root / 'scripts').mkdir(parents=True)
        shutil.copytree(ROOT / 'vendor' / 'pyrowave-metal',
                        self.root / 'vendor' / 'pyrowave-metal')
        for name in ('prepare-dependency.sh', 'verify-dependency.sh',
                     'pyrowave-metal.sha256'):
            shutil.copy2(ROOT / 'scripts' / name, self.root / 'scripts' / name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, name):
        return subprocess.run([str(self.root / 'scripts' / name)],
                              capture_output=True, text=True, check=False)

    def test_fresh_preparation_and_repeat_are_identical(self):
        first = self.run_script('prepare-dependency.sh')
        self.assertEqual(first.returncode, 0, first.stderr)
        decoder = self.root / 'generated' / 'pyrowave-metal' / 'pyrowave_decoder.mm'
        inode = decoder.stat().st_ino
        second = self.run_script('prepare-dependency.sh')
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(decoder.stat().st_ino, inode)
        self.assertEqual(self.run_script('verify-dependency.sh').returncode, 0)

    def test_corrupt_vendor_refused_before_generation(self):
        decoder = self.root / 'vendor' / 'pyrowave-metal' / 'pyrowave_decoder.mm'
        decoder.write_bytes(decoder.read_bytes() + b'altered')
        result = self.run_script('prepare-dependency.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'generated').exists())

    def test_wrong_pin_refused_before_generation(self):
        (self.root / 'vendor' / 'pyrowave-metal' / 'COMMIT').write_text('wrong\n')
        result = self.run_script('prepare-dependency.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'generated').exists())

    def test_corrupt_generated_file_refused_without_overwrite(self):
        self.assertEqual(self.run_script('prepare-dependency.sh').returncode, 0)
        decoder = self.root / 'generated' / 'pyrowave-metal' / 'pyrowave_decoder.mm'
        decoder.write_bytes(decoder.read_bytes() + b'altered')
        result = self.run_script('prepare-dependency.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(decoder.read_bytes().endswith(b'altered'))

    def test_unexpected_generated_file_refused(self):
        self.assertEqual(self.run_script('prepare-dependency.sh').returncode, 0)
        (self.root / 'generated' / 'pyrowave-metal' / 'surprise').write_text('extra')
        result = self.run_script('prepare-dependency.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected Pyrowave decoder files', result.stderr)


if __name__ == '__main__':
    unittest.main()
