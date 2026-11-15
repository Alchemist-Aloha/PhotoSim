<script setup>
import { computed, onMounted, ref } from 'vue'

const repository = 'https://github.com/Alchemist-Aloha/PhotoSim'
// Fallback when the GitHub API is unreachable or rate-limited; asset names follow PhotoSim-<version>-<suffix>.
const version = ref('1.4.1')
const release = computed(() => `${repository}/releases/download/v${version.value}`)
const file = (suffix) => `${release.value}/PhotoSim-${version.value}-${suffix}`
onMounted(async () => {
  try {
    const response = await fetch('https://api.github.com/repos/Alchemist-Aloha/PhotoSim/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    const tag = response.ok && (await response.json()).tag_name
    if (/^v\d+\.\d+\.\d+$/.test(tag)) version.value = tag.slice(1)
  } catch {
    // Keep the fallback version.
  }
})
const asset = (path) => `${import.meta.env.BASE_URL}${path}`
const activeStep = ref(0)
const steps = [
  {
    title: 'Pick your spot',
    description: 'Drop a camera on the map, aim it, and choose your sensor and lens.',
    screen: 'map',
    alt: 'PhotoSim on Linux: Yosemite map with a camera field-of-view wedge and Sun and Moon bearings.',
    caption: 'Start on the map—your camera position and lens carry straight into the 3D view.',
  },
  {
    title: 'Preview the view',
    description: 'Look through your lens over real terrain, and scrub through time to watch the sky and light shift.',
    screen: 'preview',
    alt: 'PhotoSim on Linux: a 3D Yosemite terrain preview with a 24 mm camera frame and optics controls.',
    caption: 'Real elevation and satellite imagery framed by your lens. Lighting and clouds are approximate.',
  },
  {
    title: 'Check the calendar',
    description: 'See which nights work best for the Milky Way, then save your plan or export a PNG.',
    screen: 'calendar',
    alt: 'PhotoSim on Linux: June 2026 night calendar with astronomical observing scores and source information.',
    caption: 'Night-sky scores factor in moonlight, darkness, light pollution, and an optional forecast.',
  },
]
</script>

<template>
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header page-width">
    <a class="brand" href="#" aria-label="PhotoSim home">
      <img :src="asset('icon.svg')" width="32" height="32" alt="" />
      PhotoSim
    </a>
    <nav aria-label="Main navigation">
      <a href="#workflow">How it works</a>
      <a href="#android">Android</a>
      <a :href="repository">Source <span aria-hidden="true">↗</span></a>
    </nav>
  </header>

  <main id="main">
    <section id="workflow" class="intro page-width" aria-labelledby="intro-title">
      <h1 id="intro-title">Before you go,<br /><span class="intro-accent">see what your <span class="lens">lens</span> will see.</span></h1>
      <p class="intro-copy"><strong>A free, open-source photography planner for Linux and Android.</strong><br class="desktop-break" /> Check sightlines over real terrain and time the Sun, Moon, and Milky Way.</p>
      <div class="workflow-layout">
        <div class="workflow-controls">
          <ol class="steps" aria-label="Explore the photography workflow">
            <li v-for="(step, index) in steps" :key="step.screen">
              <button
                :aria-pressed="activeStep === index"
                aria-controls="workspace-preview"
                @click="activeStep = index"
              >
                <span class="step-number" aria-hidden="true">0{{ index + 1 }}</span>
                <span class="step-body">
                  <span class="step-title">{{ step.title }}</span>
                  <span v-if="activeStep === index" class="step-description">{{ step.description }}</span>
                </span>
                <span class="step-arrow" aria-hidden="true">{{ activeStep === index ? '−' : '+' }}</span>
              </button>
            </li>
          </ol>
          <a class="button" href="#download">Get PhotoSim <span aria-hidden="true">↓</span></a>
          <p class="small-note">Free and open source. No account or API key.</p>
        </div>
        <figure id="workspace-preview" class="workspace-preview">
          <div class="desktop-screen">
            <img
              v-for="(step, index) in steps"
              v-show="activeStep === index"
              :key="step.screen"
              :src="asset(`screenshots/linux-${step.screen}.png`)"
              :alt="step.alt"
              width="1259"
              height="1021"
              fetchpriority="high"
            />
          </div>
          <figcaption aria-live="polite">
            <span class="platform-label">Linux workspace</span>
            <span>{{ steps[activeStep].caption }}</span>
          </figcaption>
        </figure>
      </div>
      <div class="location-note">
        <span>Camera, lens, and time stay synced across every tab.</span>
        <span>Shown: Yosemite Valley · 37.744° N, 119.590° W</span>
      </div>
    </section>

    <section id="android" class="android-section" aria-labelledby="android-title">
      <div class="page-width android-layout">
        <div class="android-copy">
          <h2 id="android-title">The same planner,<br />built for your phone.</h2>
          <p>Use the map, 3D terrain preview, and night calendar on Android with a touch-friendly layout.</p>
          <p>Drag to aim, pinch to zoom your focal length, and tuck the controls away when you just want to look at the frame.</p>
          <a class="text-link" href="#download">Get the Android APK <span aria-hidden="true">↓</span></a>
          <p class="android-limit">Android 10+ · Requires a compatible GPU.<br />Screenshots taken on an Android emulator.</p>
        </div>
        <div class="phone-gallery">
          <figure v-for="(screen, index) in ['map', 'preview', 'calendar']" :key="screen">
            <a :href="asset(`screenshots/android-${screen}.png`)" :aria-label="`View full-size Android ${screen} screenshot`">
              <img :src="asset(`screenshots/android-${screen}.png`)" :alt="`PhotoSim Android ${screen === 'preview' ? '3D terrain preview' : screen === 'calendar' ? 'night calendar' : 'Yosemite camera map'}`" width="1080" height="2400" loading="lazy" />
            </a>
            <figcaption>{{ ['Place the camera', 'Check the frame', 'Pick a night'][index] }}</figcaption>
          </figure>
        </div>
      </div>
    </section>

    <section class="field-notes page-width" aria-labelledby="notes-title">
      <h2 id="notes-title">A planning aid,<br />not a photograph.</h2>
      <div class="notes-copy">
        <p>Geometry is the part you can trust: camera placement, field of view, and Sun, Moon, and star positions are all calculated from your coordinates and time.</p>
        <p>Lighting, exposure, clouds, and night-sky brightness are visual approximations—and public terrain and imagery can miss small features or show old shadows. You’ll need an internet connection the first time you load a new area.</p>
        <a class="text-link" :href="`${repository}/blob/main/docs/night-calendar.md`">Read about data sources and limits <span aria-hidden="true">↗</span></a>
      </div>
    </section>

    <section id="download" class="download-section page-width" aria-labelledby="download-title">
      <div class="download-heading">
        <h2 id="download-title">Download PhotoSim</h2>
        <p>Choose your platform.<br />Latest release: <a :href="`${repository}/releases/tag/v${version}`">v{{ version }}</a></p>
      </div>
      <div class="downloads">
        <article>
          <h3>Linux</h3>
          <p>Desktop app for scouting locations and testing compositions on a larger screen.</p>
          <a class="button" :href="file('x86_64.AppImage')">Download AppImage <span aria-hidden="true">↓</span></a>
          <div class="package-links">
            <a :href="file('x86_64.deb')">Debian / Ubuntu (.deb)</a>
            <a :href="file('x86_64.pkg.tar.zst')">Arch (.pkg.tar.zst)</a>
          </div>
          <p class="small-note">x86_64 · glibc 2.39+, GTK 3, and a compatible GPU.<br />For the AppImage, mark it executable and run.</p>
        </article>
        <article>
          <h3>Android</h3>
          <p>The same tools with touch controls for phones and tablets.</p>
          <a class="button" :href="file('arm64-v8a.apk')">Download APK · ARM64 <span aria-hidden="true">↓</span></a>
          <div class="package-links">
            <a :href="file('armeabi-v7a.apk')">ARMv7 APK</a>
            <a :href="file('x86_64.apk')">x86_64 APK</a>
          </div>
          <p class="small-note">Android 10+ · Sideloaded APK (not on Google Play).<br />Allow installs from your browser or file manager when prompted.</p>
        </article>
      </div>
      <p class="release-note">Screenshots are from a development build, so the v{{ version }} release may look slightly different. <a :href="`${repository}/releases`">All releases & checksums</a> · <a :href="`${repository}/blob/main/docs/releases.md`">Install & build notes</a></p>
    </section>
  </main>

  <footer class="site-footer page-width">
    <a class="brand" href="#">PhotoSim</a>
    <p>Open-source landscape and night-sky planner.</p>
    <a :href="`${repository}/blob/main/LICENSE`">GPL-3.0-only</a>
    <a :href="repository">View on GitHub <span aria-hidden="true">↗</span></a>
  </footer>
</template>
