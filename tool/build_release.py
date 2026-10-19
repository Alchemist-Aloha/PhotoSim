#!/usr/bin/env python3
"""Build PhotoSim release artifacts using the version in pubspec.yaml."""
import argparse
import hashlib
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
DIST = BUILD / 'dist'
ABIS = ('armeabi-v7a', 'arm64-v8a', 'x86_64')
TOOLS = {
    'appimagetool': (
        'https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage',
        'ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0',
    ),
    'runtime-x86_64': (
        'https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64',
        '2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d',
    ),
}


def version_from(source):
    matches = re.findall(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?)(?:\+([0-9]+))?\s*$', source, re.M)
    if len(matches) != 1:
        raise ValueError('Expected one unquoted semantic version with optional numeric +build in pubspec.yaml')
    version, number = matches[0]
    number = int(number or 1)
    if not 1 <= number <= 2_000_000_000:
        raise ValueError('Android build number must be 1–2000000000')
    return version, number


def check_tag(version, ref):
    if ref.startswith('refs/tags/') and ref != f'refs/tags/v{version}':
        raise ValueError(f'Tag must match pubspec.yaml: expected v{version}, got {ref}')


def native_versions(version, number):
    base, _, prerelease = version.partition('-')
    arch = base if not prerelease else base + 'pre.' + prerelease.replace('-', '.')
    return version.replace('-', '~', 1) + f'-{number}', arch + f'-{number}'


def artifact_name(version, arch, extension):
    return f'PhotoSim-{version}-{arch}.{extension}'


def run(*args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def download_tool(name):
    url, expected = TOOLS[name]
    folder = BUILD / 'release-tools'
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / name
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
        temporary = target.with_suffix('.download')
        try:
            request = urllib.request.Request(url, headers={'Accept': 'application/octet-stream', 'User-Agent': 'PhotoSim-release-builder'})
            with urllib.request.urlopen(request, timeout=120) as response, temporary.open('wb') as output:
                shutil.copyfileobj(response, output)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
                raise ValueError(f'Checksum mismatch for {name}; refusing to execute it')
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    target.chmod(0o755)
    return target


def package_android(apk_dir, output, version):
    sources = [apk_dir / f'app-{abi}-release.apk' for abi in ABIS]
    for source in sources:
        if not source.is_file():
            raise FileNotFoundError(source)
    output.mkdir(parents=True, exist_ok=True)
    for abi, source in zip(ABIS, sources):
        shutil.copy2(source, output / artifact_name(version, abi, 'apk'))


def package_linux(bundle, output, version, number):
    if platform.machine() != 'x86_64':
        raise ValueError('Linux release packaging currently supports x86_64 only')
    if not (bundle / 'photosim').is_file() or not (bundle / 'lib/libapp.so').is_file():
        raise ValueError('Missing Linux release bundle; build/linux/x64/release/bundle is required')
    for command in ('dpkg-deb', 'bsdtar', 'zstd', 'desktop-file-validate', 'file'):
        if not shutil.which(command):
            raise ValueError(f'Missing packaging tool: {command}')
    appimagetool = download_tool('appimagetool')
    runtime = download_tool('runtime-x86_64')
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='release-', dir=BUILD) as work:
        appdir = Path(work) / 'PhotoSim.AppDir'
        shutil.copytree(bundle, appdir / 'usr/lib/photosim', symlinks=True)
        (appdir / 'usr/bin').mkdir(parents=True)
        (appdir / 'usr/bin/photosim').symlink_to('../lib/photosim/photosim')
        for relative in ('applications/org.photosim.photosim.desktop', 'icons/hicolor/scalable/apps/photosim.svg'):
            destination = appdir / 'usr/share' / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'packaging/linux' / destination.name, destination)
        desktop = appdir / 'usr/share/applications/org.photosim.photosim.desktop'
        run('desktop-file-validate', str(desktop))
        docs = appdir / 'usr/share/doc/photosim'
        docs.mkdir(parents=True)
        shutil.copy2(ROOT / 'README.md', docs / 'README.md')
        shutil.copytree(ROOT / 'docs', docs / 'docs')
        shutil.copy2(ROOT / 'packaging/linux/copyright', docs / 'copyright')
        shutil.copy2(ROOT / 'assets/sky/LICENSE.txt', docs / 'sky-data-LICENSE.txt')
        shutil.copy2(ROOT / 'LICENSE', docs / 'LICENSE')
        licenses = appdir / 'usr/share/licenses/photosim'
        licenses.mkdir(parents=True)
        shutil.copy2(ROOT / 'LICENSE', licenses / 'LICENSE')
        size = sum(f.stat().st_size for f in appdir.rglob('*') if f.is_file() and not f.is_symlink())
        control = appdir / 'DEBIAN'
        control.mkdir()
        deb_version, arch_version = native_versions(version, number)
        (control / 'control').write_text(
            f'Package: photosim\nVersion: {deb_version}\nArchitecture: amd64\n'
            'Maintainer: Alchemist-Aloha <Alchemist-Aloha@users.noreply.github.com>\n'
            f'Installed-Size: {(size + 1023) // 1024}\nSection: graphics\nPriority: optional\n'
            'Homepage: https://github.com/Alchemist-Aloha/PhotoSim\n'
            'Depends: libc6 (>= 2.39), libstdc++6 (>= 13), libgtk-3-0t64 | libgtk-3-0, libegl1, libgles2, libgl1, libvulkan1\n'
            'Description: Landscape and astrophotography planner\n'
            ' Plan compositions, celestial geometry and observing windows on Linux.\n'
        )
        run('dpkg-deb', '--build', '--root-owner-group', str(appdir), str(output / artifact_name(version, 'x86_64', 'deb')))
        shutil.rmtree(control)
        # A prerelease must sort below the final version in both package managers.
        (appdir / '.PKGINFO').write_text(
            f'pkgname = photosim\npkgbase = photosim\npkgver = {arch_version}\n'
            'pkgdesc = Landscape and astrophotography planner\n'
            'url = https://github.com/Alchemist-Aloha/PhotoSim\n'
            f'builddate = {int(os.environ.get("SOURCE_DATE_EPOCH", str(int(time.time()))))}\nsize = {size}\n'
            'arch = x86_64\nlicense = GPL-3.0-only\n'
            'depend = glibc>=2.39\ndepend = gcc-libs\ndepend = gtk3\ndepend = libglvnd\ndepend = vulkan-icd-loader\n'
        )
        run('bsdtar', '--uid', '0', '--gid', '0', '--uname', 'root', '--gname', 'root', '--zstd', '-cf',
            str(output / artifact_name(version, 'x86_64', 'pkg.tar.zst')), '-C', str(appdir), '.PKGINFO', 'usr')
        (appdir / '.PKGINFO').unlink()
        (appdir / 'AppRun').symlink_to('usr/lib/photosim/photosim')
        (appdir / desktop.name).symlink_to('usr/share/applications/' + desktop.name)
        (appdir / 'photosim.svg').symlink_to('usr/share/icons/hicolor/scalable/apps/photosim.svg')
        (appdir / '.DirIcon').symlink_to('photosim.svg')
        run(str(appimagetool), '--appimage-extract-and-run', '--no-appstream', '--runtime-file', str(runtime),
            str(appdir), str(output / artifact_name(version, 'x86_64', 'AppImage')),
            env={**os.environ, 'ARCH': 'x86_64', 'VERSION': version})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=('metadata', 'linux', 'android'))
    parser.add_argument('--skip-build', action='store_true', help='Package an already-built release bundle/APKs')
    args = parser.parse_args()
    version, number = version_from((ROOT / 'pubspec.yaml').read_text())
    check_tag(version, os.environ.get('GITHUB_REF', ''))
    if args.platform == 'metadata':
        print(f'version={version}\nbuild_number={number}')
        return
    BUILD.mkdir(exist_ok=True)
    if not args.skip_build:
        run('flutter', 'pub', 'get', '--enforce-lockfile', cwd=ROOT)
        command = ['flutter', 'build', 'apk' if args.platform == 'android' else 'linux', '--release',
                   f'--build-name={version}', f'--build-number={number}']
        if args.platform == 'android':
            command.append('--split-per-abi')
        run(*command, cwd=ROOT)
    if args.platform == 'linux':
        package_linux(BUILD / 'linux/x64/release/bundle', DIST, version, number)
    else:
        package_android(BUILD / 'app/outputs/flutter-apk', DIST, version)


if __name__ == '__main__':
    main()
