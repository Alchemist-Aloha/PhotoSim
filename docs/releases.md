# Builds and GitHub releases

`.github/workflows/build.yml` checks pushes to `main`/`master`, pull requests,
`v*` tags, published GitHub releases, and manual runs. It pins Flutter 3.47.6,
checks formatting/analysis/tests, builds both platforms and retains workflow
artifacts. Only **tag refs** publish release assets; a manual run on a branch
builds artifacts without publishing.

## Release procedure

1. Configure the four Android signing secrets below once.
2. Update `pubspec.yaml`, increasing both the public version and numeric build
   number, e.g. `version: 0.2.0+2`. Commit the change.
3. Push the matching tag: `git tag v0.2.0 && git push origin v0.2.0`.
4. After both platform jobs succeed, the workflow creates the GitHub release
   (or adds files to an existing release) and uploads binaries, a tagged source
   archive and `SHA256SUMS`.

The tag **must match the version before `+`**. A mismatch fails before builds.
Prerelease versions such as `0.2.0-rc.1+2` use tag `v0.2.0-rc.1`; automatically
created releases are marked prerelease. A published release on an existing tag
also triggers the build. Rerunning on a tag replaces matching asset names using
`gh release upload --clobber`; unrelated assets are not deleted. No release is
created by the workflow if a build fails or a required artifact is missing.

The release job alone has `contents: write`, using GitHub's automatic token;
no personal access token is needed. Repository/org policy must permit Actions
and its release-write permission. Protect `v*` tags so only trusted maintainers
can publish. Signing secrets are exposed only to tag builds, not branch/PR builds.
Actions are pinned by commit. AppImage tools
and the runtime are pinned by release and verified SHA-256 before use.

## Artifact names

For version `0.2.0+2`, filenames use public version `0.2.0`:

| File | Platform |
|---|---|
| `PhotoSim-0.2.0-x86_64.deb` | Debian/Ubuntu amd64 |
| `PhotoSim-0.2.0-x86_64.pkg.tar.zst` | Arch/pacman x86_64 |
| `PhotoSim-0.2.0-x86_64.AppImage` | Linux x86_64 |
| `PhotoSim-0.2.0-armeabi-v7a.apk` | Android ARMv7 |
| `PhotoSim-0.2.0-arm64-v8a.apk` | Android ARM64 |
| `PhotoSim-0.2.0-x86_64.apk` | Android x86_64 |

The pacman filename intentionally follows the requested convention rather than
Arch's usual filename; `pacman -U` reads version/build metadata from `.PKGINFO`.
Native package revisions use the pubspec build number. Prereleases use Debian's
`~` and Arch's `pre.` spelling internally so they sort below the final version.

Linux builds use Ubuntu 24.04: the baseline is glibc 2.39+, GTK 3 and a compatible
Impeller graphics driver. Debian/pacman packages declare runtime dependencies.
The AppImage bundles the Flutter application, **not GTK or graphics drivers**;
it needs those host libraries too, and is not a promise of compatibility with
older distributions. Linux ARM builds are not included. Android remains API 29+;
a matching CPU ABI does not guarantee that an older GPU can run Flutter GPU.

Install with `sudo apt install ./PhotoSim-...deb`, `sudo pacman -U PhotoSim-...pkg.tar.zst`,
or `chmod +x PhotoSim-...AppImage` then run it. The AppImage can also use
`--appimage-extract-and-run` when FUSE is unavailable. Linux packages install
under `/usr/lib/photosim` with `/usr/bin/photosim` and a desktop launcher; they
do not modify application-support files containing plans or session recovery.

## Android signing (required for tag releases)

In repository **Settings → Secrets and variables → Actions**, add:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded signing keystore file.
- `ANDROID_KEYSTORE_PASSWORD`: keystore password.
- `ANDROID_KEY_ALIAS`: signing alias.
- `ANDROID_KEY_PASSWORD`: key password.

Use a permanent private key and keep an independent secure backup. To create
one, run the following interactively, then encode it on Linux:

```sh
keytool -genkeypair -keystore photosim-release.jks -alias photosim \
  -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 photosim-release.jks
```

Never commit a keystore or passwords.
The workflow decodes it only into runner temporary storage and removes it after
the build. Missing signing secrets fail tag releases instead of publishing APKs
signed with an ephemeral CI development key.

**Signing identity must stay the same to update existing Android installations.**
Old development-signed APKs cannot be updated using a different release key.
Uninstalling deletes app-private plans and session state: do not uninstall blindly;
back up your data before any signing-key migration. Increment the build number
for each release. Non-tag builds remain development-signed CI
artifacts, not official release updates. This workflow publishes sideloadable
APKs, not Play Store bundles or a Play Store submission.

## Local builds

On Ubuntu 24.04 install Flutter 3.47.6, the Android SDK/JDK 17 for APKs, and:

```sh
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libstdc++-13-dev dpkg-dev libarchive-tools zstd desktop-file-utils file
python3 tool/build_release.py linux
python3 tool/build_release.py android
```

Outputs are under `build/dist/`. `--skip-build` packages an existing release
bundle or split APKs. For local release signing, export `PHOTOSIM_KEYSTORE_FILE`,
`PHOTOSIM_KEYSTORE_PASSWORD`, `PHOTOSIM_KEY_ALIAS` and `PHOTOSIM_KEY_PASSWORD`.
Without them, the existing development key is used. Partial signing configuration
is rejected. Optional `SOURCE_DATE_EPOCH` controls package build metadata; CI
sets it to the commit timestamp. This is not a bit-for-bit reproducibility claim.

Check the packaging logic with:
`python3 -m unittest discover -s tool -p 'test_*.py'`.

PhotoSim uses **GPL-3.0-only**; the full license is bundled in every app and
Linux package, with SPDX metadata in the pacman package. Third-party components
and sky data retain their original notices. Each GitHub release includes a
`PhotoSim-<version>-source.tar.gz` archive of the exact tagged repository, including
build scripts, lockfile and license. Flutter/dependency versions are pinned as
shown above. Distributors must also satisfy corresponding-source obligations for
any bundled non-system dependencies; a complete dependency-license audit has not
been performed.
