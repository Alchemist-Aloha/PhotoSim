<script setup>
import { ref } from 'vue'

const repository = 'https://github.com/Alchemist-Aloha/PhotoSim'
const release = `${repository}/releases/download/v1.1.1`
const asset = (path) => `${import.meta.env.BASE_URL}${path}`
const activeStep = ref(0)
const steps = [
  {
    title: 'Find your position',
    description: 'Choose a place on the map. Set your camera, lens and direction.',
    screen: 'map',
    alt: 'PhotoSim on Linux: Yosemite map with a camera field-of-view wedge and Sun and Moon bearings.',
    caption: 'Start on the map. The camera and lens carry through to the preview.',
  },
  {
    title: 'Follow the light',
    description: 'Explore the terrain in 3D. Change the time and see how the sky and approximate lighting respond.',
    screen: 'preview',
    alt: 'PhotoSim on Linux: a 3D Yosemite terrain preview with a 24 mm camera frame and optics controls.',
    caption: 'Frame real terrain with your chosen lens. Lighting is an approximation.',
  },
  {
    title: 'Choose your moment',
    description: 'Compare night-sky windows in the calendar. Save a named plan or export an attributed PNG.',
    screen: 'calendar',
    alt: 'PhotoSim on Linux: June 2026 night calendar with astronomical observing scores and source information.',
    caption: 'Compare calculated night-sky opportunities, with the assumptions in view.',
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
      <a href="#workflow">The workflow</a>
      <a href="#android">On Android</a>
      <a :href="repository">Source <span aria-hidden="true">↗</span></a>
    </nav>
  </header>

  <main id="main">
    <section id="workflow" class="intro page-width" aria-labelledby="intro-title">
      <h1 id="intro-title">Before you go,<br />see how the shot comes together.</h1>
      <p class="intro-copy">A landscape photography planner for Linux and Android.<br class="desktop-break" /> Explore a place, frame the terrain, and find your light.</p>
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
          <p class="small-note">Open source. No account required.</p>
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
        <span>One camera. One lens. One shared time.</span>
        <span>Shown in Yosemite · 37.744° N, 119.590° W</span>
      </div>
    </section>

    <section id="android" class="android-section" aria-labelledby="android-title">
      <div class="page-width android-layout">
        <div class="android-copy">
          <h2 id="android-title">The same tools.<br />A little closer to the trail.</h2>
          <p>PhotoSim adapts to your Android phone: a map to place the camera, a terrain preview to explore the frame, and a calendar to compare the night sky.</p>
          <p>Drag to aim. Pinch to change focal length. Open the controls when you need them; keep the view when you don’t.</p>
          <a class="text-link" href="#download">Get the Android APK <span aria-hidden="true">↓</span></a>
          <p class="android-limit">Android 10+ · Compatible graphics hardware required.<br />Screenshots captured on an Android emulator.</p>
        </div>
        <div class="phone-gallery">
          <figure v-for="(screen, index) in ['map', 'preview', 'calendar']" :key="screen">
            <a :href="asset(`screenshots/android-${screen}.png`)" :aria-label="`View full-size Android ${screen} screenshot`">
              <img :src="asset(`screenshots/android-${screen}.png`)" :alt="`PhotoSim Android ${screen === 'preview' ? '3D terrain preview' : screen === 'calendar' ? 'night calendar' : 'Yosemite camera map'}`" width="1080" height="2400" loading="lazy" />
            </a>
            <figcaption>{{ ['Place the camera', 'Explore the frame', 'Compare the nights'][index] }}</figcaption>
          </figure>
        </div>
      </div>
    </section>

    <section class="field-notes page-width" aria-labelledby="notes-title">
      <h2 id="notes-title">A planning tool.<br />Not a promise of the view.</h2>
      <div class="notes-copy">
        <p>Terrain and imagery give your composition a place. Locally calculated Sun, Moon and night-sky positions give it a time. Sensor size and focal length give it a frame.</p>
        <p>The 3D preview, lighting and manual weather effects are approximate, not a calibrated photograph or a weather forecast. Uncached maps, terrain and imagery need an internet connection.</p>
        <a class="text-link" :href="`${repository}/blob/main/docs/night-calendar.md`">Read the sources and limits <span aria-hidden="true">↗</span></a>
      </div>
    </section>

    <section id="download" class="download-section page-width" aria-labelledby="download-title">
      <div class="download-heading">
        <h2 id="download-title">Your next photograph<br />starts with a plan.</h2>
        <p>Get PhotoSim for your platform.<br />Published release: <a :href="`${repository}/releases/tag/v1.1.1`">v1.1.1</a></p>
      </div>
      <div class="downloads">
        <article>
          <h3>Linux</h3>
          <p>A full workspace for exploring locations and refining your composition.</p>
          <a class="button" :href="`${release}/PhotoSim-1.1.1-x86_64.AppImage`">Download AppImage <span aria-hidden="true">↓</span></a>
          <div class="package-links">
            <a :href="`${release}/PhotoSim-1.1.1-x86_64.deb`">Debian / Ubuntu (.deb)</a>
            <a :href="`${release}/PhotoSim-1.1.1-x86_64.pkg.tar.zst`">Arch (.pkg.tar.zst)</a>
          </div>
          <p class="small-note">x86_64 · glibc 2.39+, GTK 3 and a compatible GPU.<br />AppImage: make executable, then run.</p>
        </article>
        <article>
          <h3>Android</h3>
          <p>The same planning workflow, with touch controls and a phone-sized workspace.</p>
          <a class="button" :href="`${release}/PhotoSim-1.1.1-arm64-v8a.apk`">Download APK · ARM64 <span aria-hidden="true">↓</span></a>
          <div class="package-links">
            <a :href="`${release}/PhotoSim-1.1.1-armeabi-v7a.apk`">ARMv7 APK</a>
            <a :href="`${release}/PhotoSim-1.1.1-x86_64.apk`">x86_64 APK</a>
          </div>
          <p class="small-note">Android 10+ · Sideloaded APK, not a Play Store app.<br />Allow installation from your browser when prompted.</p>
        </article>
      </div>
      <p class="release-note">Screenshots show a development build; the published release may differ. <a :href="`${repository}/releases`">All releases & checksums</a> · <a :href="`${repository}/blob/main/docs/releases.md`">Installation & build notes</a></p>
    </section>
  </main>

  <footer class="site-footer page-width">
    <a class="brand" href="#">PhotoSim</a>
    <p>Made for the photograph you haven’t taken yet.</p>
    <a :href="`${repository}/blob/main/LICENSE`">GPL-3.0-only</a>
    <a :href="repository">View on GitHub <span aria-hidden="true">↗</span></a>
  </footer>
</template>
