import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

import build_release as release


class ReleaseTests(unittest.TestCase):
    def test_version_and_tag_are_consistent(self):
        self.assertEqual(release.version_from('name: photosim\nversion: 1.2.3+4\n'), ('1.2.3', 4))
        self.assertEqual(release.version_from('version: 1.2.3-rc.1+5\n'), ('1.2.3-rc.1', 5))
        release.check_tag('1.2.3', 'refs/tags/v1.2.3')
        release.check_tag('1.2.3', 'refs/heads/main')
        with self.assertRaises(ValueError):
            release.check_tag('1.2.3', 'refs/tags/v2.0.0')
        for source in ('version: ../bad', 'version: 1.2.3+0', 'version: 1.2.3+9999999999', 'version: 1.2.3\nversion: 2.0.0'):
            with self.assertRaises(ValueError):
                release.version_from(source)

    def test_native_prerelease_versions(self):
        self.assertEqual(release.native_versions('1.2.3', 4), ('1.2.3-4', '1.2.3-4'))
        self.assertEqual(release.native_versions('1.2.3-rc.1', 5), ('1.2.3~rc.1-5', '1.2.3pre.rc.1-5'))

    def test_names_and_android_artifacts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, output = root / 'apk', root / 'dist'
            source.mkdir()
            for abi in release.ABIS:
                (source / f'app-{abi}-release.apk').write_bytes(abi.encode())
            release.package_android(source, output, '1.2.3')
            self.assertEqual(sorted(f.name for f in output.iterdir()), sorted(
                f'PhotoSim-1.2.3-{abi}.apk' for abi in release.ABIS))
            for abi in release.ABIS:
                self.assertEqual((output / f'PhotoSim-1.2.3-{abi}.apk').read_bytes(), abi.encode())
            self.assertEqual(release.artifact_name('1.2.3', 'x86_64', 'pkg.tar.zst'), 'PhotoSim-1.2.3-x86_64.pkg.tar.zst')

    def test_missing_apk_does_not_produce_partial_outputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'app-armeabi-v7a-release.apk').write_bytes(b'first')
            with self.assertRaises(FileNotFoundError):
                release.package_android(root, root / 'out', '1.2.3')
            self.assertFalse((root / 'out').exists())

    def test_downloaded_tools_must_match_pinned_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(release, 'BUILD', Path(folder)), patch('urllib.request.urlopen') as request:
                request.return_value.__enter__.return_value.read.side_effect = [b'wrong binary', b'']
                with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                    release.download_tool('appimagetool')
                self.assertFalse((Path(folder) / 'release-tools/appimagetool').exists())
                self.assertFalse((Path(folder) / 'release-tools/appimagetool.download').exists())

    def test_linux_rejects_wrong_architecture(self):
        with patch('platform.machine', return_value='aarch64'):
            with self.assertRaisesRegex(ValueError, 'x86_64 only'):
                release.package_linux(Path('unused'), Path('unused'), '1.2.3', 1)


if __name__ == '__main__':
    unittest.main()
