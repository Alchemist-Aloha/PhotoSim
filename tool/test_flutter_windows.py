from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import flutter_windows as windows


class FrameworkPatchTests(unittest.TestCase):
    def test_sdk_is_restored_after_success_and_failure(self):
        for fail in (False, True):
            with self.subTest(fail=fail), tempfile.TemporaryDirectory() as directory:
                sdk = Path(directory)
                source = sdk / windows.SEMANTICS
                source.parent.mkdir(parents=True)
                source.write_bytes(b'original source\r\n')

                def git(*args, **kwargs):
                    if '--check' not in args[0]:
                        source.write_bytes(b'patched source\n')

                with patch.object(windows.subprocess, 'run', side_effect=git):
                    try:
                        with windows.patched_framework(sdk):
                            self.assertEqual(source.read_bytes(), b'patched source\n')
                            if fail:
                                raise RuntimeError('test build failure')
                    except RuntimeError:
                        self.assertTrue(fail)
                self.assertEqual(source.read_bytes(), b'original source\r\n')

    def test_fixed_sdk_is_left_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            source = sdk / windows.SEMANTICS
            source.parent.mkdir(parents=True)
            original = b'if (node._isSkippedInHitTestTree()) { }\n'
            source.write_bytes(original)
            with patch.object(windows.subprocess, 'run') as git:
                with windows.patched_framework(sdk):
                    self.assertEqual(source.read_bytes(), original)
                git.assert_not_called()
            self.assertEqual(source.read_bytes(), original)

    def test_incompatible_sdk_fails_without_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            source = sdk / windows.SEMANTICS
            source.parent.mkdir(parents=True)
            source.write_bytes(b'unrecognized source')
            failure = subprocess.CalledProcessError(1, 'git', stderr=b'hunk does not apply')
            with patch.object(windows.subprocess, 'run', side_effect=failure):
                with self.assertRaisesRegex(ValueError, 'does not apply cleanly'):
                    with windows.patched_framework(sdk):
                        self.fail('An incompatible SDK must not be used')
            self.assertEqual(source.read_bytes(), b'unrecognized source')


if __name__ == '__main__':
    unittest.main()
