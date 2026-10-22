import tempfile
import subprocess
from pathlib import Path
import unittest
import zipfile
from unittest.mock import patch

import build_release as release


class ReleaseTests(unittest.TestCase):
    def make_windows_bundle(self, bundle):
        for relative in (
            'photosim.exe', 'flutter_windows.dll', 'data/app.so',
            'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin',
            'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
        ):
            target = bundle / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(relative.encode())

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

    def test_windows_archive_contains_complete_bundle_and_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, output = root / 'bundle', root / 'out'
            files = (
                'photosim.exe', 'flutter_windows.dll', 'data/app.so',
                'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin',
                'data/flutter_assets/assets/sky/stars.json',
                'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
            )
            for relative in files:
                target = bundle / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(relative.encode())
            release.package_windows(bundle, output, '1.2.3')
            archive = output / 'PhotoSim-1.2.3-windows-x64.zip'
            with zipfile.ZipFile(archive) as package:
                self.assertIsNone(package.testzip())
                for relative in files:
                    self.assertEqual(package.read(f'PhotoSim-1.2.3-windows-x64/{relative}'), relative.encode())
                self.assertIn('PhotoSim-1.2.3-windows-x64/LICENSE', package.namelist())
                self.assertIn('PhotoSim-1.2.3-windows-x64/README.md', package.namelist())
            digest = release.hashlib.sha256(archive.read_bytes()).hexdigest()
            self.assertEqual(archive.with_suffix('.zip.sha256').read_text(), f'{digest}  {archive.name}\n')

    def test_missing_windows_bundle_does_not_produce_partial_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaisesRegex(ValueError, 'photosim.exe'):
                release.package_windows(root, root / 'out', '1.2.3')
            self.assertFalse((root / 'out').exists())

    def test_windows_numeric_versions_and_limits(self):
        self.assertEqual(release.windows_version('1.2.3', 4), '1.2.3.4')
        self.assertEqual(release.windows_version('1.2.3-rc.1', 5), '1.2.3.5')
        for version, number in (('65536.0.0', 1), ('1.2.3', 65536)):
            with self.assertRaisesRegex(ValueError, '0–65535'):
                release.windows_version(version, number)

    def test_windows_installer_receives_version_and_paths_and_emits_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, output = root / 'release bundle', root / 'dist'
            self.make_windows_bundle(bundle)

            def compile_installer(*args, **kwargs):
                destination = Path(next(arg[2:] for arg in args if arg.startswith('/O')))
                name = next(arg[2:] for arg in args if arg.startswith('/F')) + '.exe'
                (destination / name).write_bytes(b'compiled installer')

            with patch.object(release, 'find_iscc', return_value='ISCC.exe'), \
                    patch.object(release, 'run', side_effect=compile_installer) as compiler:
                release.build_windows_installer(bundle, output, '1.2.3-rc.1', 5)
            args = compiler.call_args.args
            self.assertIn('/DAppVersion=1.2.3-rc.1', args)
            self.assertIn('/DAppNumericVersion=1.2.3.5', args)
            self.assertIn(f'/DBundleDir={bundle.resolve()}', args)
            artifact = output / 'PhotoSim-1.2.3-rc.1-windows-x64-setup.exe'
            self.assertEqual(artifact.read_bytes(), b'compiled installer')
            digest = release.hashlib.sha256(artifact.read_bytes()).hexdigest()
            self.assertEqual(artifact.with_suffix('.exe.sha256').read_text(), f'{digest}  {artifact.name}\n')
            self.assertEqual(sorted(path.name for path in output.iterdir()), [artifact.name, artifact.name + '.sha256'])

    def test_installer_failure_does_not_publish_partial_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle, output = root / 'bundle', root / 'dist'
            self.make_windows_bundle(bundle)
            output.mkdir()
            artifact = output / 'PhotoSim-1.2.3-windows-x64-setup.exe'
            artifact.write_bytes(b'previous installer')
            with patch.object(release, 'find_iscc', return_value='ISCC.exe'), \
                    patch.object(release, 'run', side_effect=subprocess.CalledProcessError(2, 'ISCC.exe')):
                with self.assertRaises(subprocess.CalledProcessError):
                    release.build_windows_installer(bundle, output, '1.2.3', 1)
            self.assertEqual(artifact.read_bytes(), b'previous installer')
            self.assertEqual(list(output.iterdir()), [artifact])

    def test_invalid_explicit_inno_compiler_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            compiler = Path(folder) / 'missing-ISCC.exe'
            with patch.dict('os.environ', {'ISCC': str(compiler)}):
                with self.assertRaisesRegex(ValueError, 'ISCC does not point'):
                    release.find_iscc()


if __name__ == '__main__':
    unittest.main()
