# PhotoSim for Windows

## Run the portable app

Extract `PhotoSim-<version>-windows-x64.zip` into a writable folder, then open
`photosim.exe` inside the extracted folder. Keep the executable, DLLs and `data`
folder together. The ZIP includes the Visual C++ runtime DLLs; Flutter does not
need to be installed to run it.

This build targets Windows 10/11 x64 and requires a graphics driver compatible
with Flutter's Impeller renderer. The Windows runner enables Impeller and
Flutter GPU in both debug and release builds. Rendering performance and driver
compatibility can vary between computers.

The desktop controls match Linux: click the map to place the camera, drag the
3D preview to aim, and hold WASD while the preview has focus to move. Fullscreen
preview fills the current monitor; Esc restores the previous window placement.
Export PNG opens a path dialog, initially pointing to Downloads. Plans, session
recovery and cached imagery use the current Windows user's application folders.
Online maps, terrain, imagery and forecasts require internet access.

## Build from source

Install Flutter 3.47.1 or newer (local Windows build: 3.47.7), Visual Studio's
Desktop development with C++ workload, and the Windows SDK. Python 3 is required
for the release packaging script. Install Inno Setup 6 to build the EXE installer.
The release script finds `ISCC.exe` on PATH or in the usual Inno Setup 6 install
folders. Set the `ISCC` environment variable to its full path for other locations.

```powershell
flutter pub get --enforce-lockfile
python tool/flutter_windows.py build windows --release
python tool/build_release.py windows --skip-build --installer
```

Or build and package in one command:

```powershell
python tool/build_release.py windows --installer
```

The Windows builder temporarily applies the upstream Flutter accessibility fix
[#193372](https://github.com/flutter/flutter/pull/193372), then restores the SDK
source. Flutter 3.47.6/3.47.7 do not include it. Use the wrapper shown above for
direct Flutter builds and native tests; a plain `flutter build windows` bypasses
the backport. Run commands serially when they share a Flutter SDK. The wrapper
skips SDKs that already include the fix and stops if the patch is incompatible.
The source repository records the crash diagnosis in
`docs/windows-crash-diagnosis.md` and backport details in `tool/patches/README.md`.

The executable is `build/windows/x64/runner/Release/photosim.exe`. The portable
ZIP, EXE installer and their SHA-256 checksums are written to `build/dist/`. Omit
`--installer` to package only the portable ZIP. The archive includes
the complete release folder, this guide and the GPL license.

## EXE installer and GitHub Actions

`PhotoSim-<version>-windows-x64-setup.exe` installs for the current user under
`%LOCALAPPDATA%\Programs\PhotoSim` without requesting administrator privileges.
It adds a Start menu shortcut and a Windows uninstall entry; a desktop shortcut
is optional. Updates use the same application ID. Uninstall removes installed
program files and keeps application-support files containing plans, session
recovery and caches. Windows packages are currently unsigned.

The `windows` job in `.github/workflows/build.yml` runs on `windows-2025`, using
the workflow's pinned Flutter SDK and the runner's Inno Setup 6 compiler. It
builds both packages, silently installs into a temporary folder, verifies every
installed release-bundle file by SHA-256 and uninstalls it before uploading the
`windows-x64` workflow artifact. The hosted job does not run GPU integration
tests. Pull requests, branch pushes and manual runs keep the files as workflow
artifacts. Matching version tags also publish both packages and checksums to
GitHub Releases after Linux, Windows and Android jobs succeed.

Run the installer check locally in a clean user account (the test refuses to
overwrite an existing PhotoSim installation):

```powershell
./tool/test_windows_installer.ps1 `
  -InstallerPath build/dist/PhotoSim-1.1.1-windows-x64-setup.exe `
  -BundleDirectory build/windows/x64/runner/Release `
  -InstallDirectory build/validation/installer-test
```

## Validation

The local Windows build was checked with Flutter 3.47.7 and Visual Studio Build
Tools 2026. The native integration test renders fixture terrain and imagery,
checks fullscreen entry/restoration and saves a PNG through the export dialog:

```powershell
flutter analyze --fatal-infos --fatal-warnings
flutter test
python tool/flutter_windows.py test integration_test/windows_workflow_test.dart -d windows
python tool/flutter_windows.py test integration_test/windows_scene_regression_test.dart -d windows
python -m unittest discover -s tool -p 'test_*.py'
```

Integration-test screenshots are written to `build/validation/windows/`. The
portable ZIP was also extracted, checked against every release-bundle file and
started successfully. The scene regression test uses real network terrain and
imagery, activates the native Windows accessibility bridge, and exercises slider
section animations, inspector visibility, Map/3D re-entry and fullscreen. It
checks that all nine terrain and imagery tiles load and rendering continues.
These tests cover local x64 operation; other GPUs, Windows machines and complete
screen-reader interaction have not been tested.
