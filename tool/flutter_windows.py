#!/usr/bin/env python3
"""Run Flutter with the upstream Windows accessibility fix, restoring the SDK afterwards."""
from contextlib import contextmanager
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SEMANTICS = 'packages/flutter/lib/src/semantics/semantics.dart'
PATCH = ROOT / 'tool/patches/flutter-193372-semantics.patch'


@contextmanager
def patched_framework(sdk=None):
    if sdk is None:
        flutter = shutil.which('flutter')
        if not flutter:
            raise ValueError('Flutter is not on PATH')
        sdk = Path(flutter).resolve().parents[1]
    source = Path(sdk) / SEMANTICS
    original = source.read_bytes()
    # Flutter master includes this fix from PR #193372; newer SDKs need no patch.
    if b'node._isSkippedInHitTestTree()' in original:
        yield
        return
    command = ['git', '-C', str(sdk), 'apply', f'--include={SEMANTICS}']
    try:
        subprocess.run([*command, '--check', str(PATCH)], check=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        raise ValueError(
            'This Flutter SDK does not contain the accessibility fix and the '
            'backport does not apply cleanly. Use a fixed SDK or review PR #193372.\n'
            + error.stderr.decode(errors='replace')
        ) from error
    subprocess.run([*command, str(PATCH)], check=True)
    patched = source.read_bytes()
    print('Using Flutter accessibility backport #193372 for this command.', flush=True)
    try:
        yield
    finally:
        if source.read_bytes() != patched:
            raise RuntimeError('Flutter source changed during the build; refusing to overwrite it.')
        source.write_bytes(original)
        print('Restored the original Flutter SDK source.', flush=True)


def main():
    if len(sys.argv) < 2:
        raise SystemExit('Usage: python tool/flutter_windows.py <flutter command and arguments>')
    with patched_framework():
        result = subprocess.run([shutil.which('flutter') or 'flutter', *sys.argv[1:]])
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
