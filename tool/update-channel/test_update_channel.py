import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('update_channel', Path(__file__).parents[1] / 'update_channel.py')
channel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(channel)


class UpdateChannelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.package = self.directory / 'FlClash-0.9.1-windows-amd64.zip'
        self.package.write_bytes(b'package fixture')
        channel.prepare(str(self.package), '0.9.1', '12', 'a' * 40)

    def change(self, **values):
        path = self.directory / 'build-info.json'
        manifest = json.loads(path.read_text())
        manifest.update(values)
        path.write_text(json.dumps(manifest))

    def test_round_trip(self):
        self.assertEqual(channel.validate(self.directory)['build'], 12)

    def test_modified_package_fails(self):
        self.package.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            channel.validate(self.directory)

    def test_path_traversal_fails(self):
        self.change(file='../FlClash-0.9.1-windows-amd64.zip')
        with self.assertRaisesRegex(ValueError, 'filename'):
            channel.validate(self.directory)

    def test_invalid_release_metadata_fails(self):
        for values in [dict(version='0.9.1; bad'), dict(build=True), dict(build=0), dict(source='main')]:
            with self.subTest(values=values):
                channel.prepare(str(self.package), '0.9.1', '12', 'a' * 40)
                self.change(**values)
                with self.assertRaises(ValueError):
                    channel.validate(self.directory)

    def test_checksum_file_must_match(self):
        (self.directory / 'SHA256SUMS.txt').write_text('wrong')
        with self.assertRaisesRegex(ValueError, 'Checksum file'):
            channel.validate(self.directory)

    def test_missing_and_empty_packages_fail(self):
        self.package.write_bytes(b'')
        with self.assertRaisesRegex(ValueError, 'Empty package'):
            channel.validate(self.directory)
        self.package.unlink()
        with self.assertRaisesRegex(ValueError, 'Missing package'):
            channel.validate(self.directory)

    def test_versions_cannot_make_an_older_build_latest(self):
        self.assertGreater(channel.release_key('build-v0.9.1+13'), channel.release_key('build-v0.9.1+12'))
        self.assertGreater(channel.release_key('build-v0.9.2+1'), channel.release_key('build-v0.9.1+999'))
        with self.assertRaises(ValueError):
            channel.release_key('v0.9.1')


if __name__ == '__main__':
    unittest.main()
