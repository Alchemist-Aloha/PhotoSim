# PhotoSim website

Vue 3 + Vite presentation site for the Linux and Android apps. No backend, account, analytics, external fonts, or API keys.

## Run locally

Use Node.js 22.12+ and npm:

```sh
cd website
npm ci
npm run dev
```

## Build and check

```sh
npm run build
npx playwright install chromium
npm test
npm run preview
```

Publish the contents of `dist/` to a static host. Vite uses a relative asset base, so it can be hosted at the domain root or a subdirectory. No SPA fallback or server routing is required.

The Playwright checks exercise the three workflow views, download destinations, image loading, keyboard skip link, and horizontal overflow at desktop and phone sizes. To also capture the page for visual review:

```sh
SHOWCASE_CAPTURE=1 npm test
```

Captures go to the repository's gitignored `.impeccable/review/{desktop,mobile}.png`.

## GitHub Pages

Live site: https://alchemist-aloha.github.io/PhotoSim/

`.github/workflows/pages.yml` builds, tests, and publishes this site on pushes to
`main` that change `website/` or the deployment workflow. It can also be run
manually from GitHub Actions → Deploy website. Repository Pages settings use
**GitHub Actions** as the build source; no separate hosting branch is needed.

## Screenshots

`public/screenshots/` contains six real application captures, not generated mockups:

| Platform | Screens | Capture |
| --- | --- | --- |
| Linux | Map, 3D preview, night calendar | Flutter Linux application, 1259 × 1021 |
| Android | Map, 3D preview, night calendar | Android emulator via `adb screencap`, 1080 × 2400 |

Captured November 2, 2026 from this development checkout. The scene is Yosemite, June 21, 2026 at 19:00 UTC, with a 24 mm lens. Map and terrain attribution is retained in the app UI. The calendar reflects the selected date's actual computed result; it is not an invented “perfect night.” The screenshots do not claim to be photographs or weather forecasts.

The capture test uses temporary saved plans and does not persist an app session. Run it from the repository root with the project's Flutter prerequisites installed and working graphics/network access:

```sh
flutter test integration_test/showcase_test.dart -d linux
```

Linux writes its three PNGs directly. For Android, boot a compatible emulator or connect a device, then:

```sh
flutter test integration_test/showcase_test.dart -d <device-id>
```

In another terminal, watch for `SHOWCASE_READY:map`, `SHOWCASE_READY:preview`, and `SHOWCASE_READY:calendar`. Each pauses for 15 seconds. After the corresponding marker, capture the device (replace `map` for each screen):

```sh
adb -s <device-id> exec-out screencap -p > website/public/screenshots/android-map.png
```

Inspect each new screenshot for loaded terrain/imagery and retained attribution. Recapturing overwrites the PNGs and their provenance metadata. When using the repository's Impeccable tooling, re-embed the platform, capture method, checkout date, and scene origin with `impeccable embed-prompt <image> --prompt '<origin>'`.

## Updates and licenses

Download URLs are deliberately pinned to the verified published **v1.1.1** assets in `src/App.vue`. Update the version and asset names together after confirming a new release. The page explicitly distinguishes development screenshots from the published release.

Typography is the app's bundled Source Sans 3; its license is in `public/fonts/OFL.txt`. App icon and screenshot UI are from this repository. Project license: [GPL-3.0-only](../LICENSE).
