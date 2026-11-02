---
name: PhotoSim
description: The Scouting Desk — a precise, calm photographic planning workspace.
colors:
  copper-seed: "#A65332"
  primary-light: "#8F4C33"
  on-primary-light: "#FFFFFF"
  primary-container-light: "#FFDBCF"
  on-primary-container-light: "#71361E"
  primary-dark: "#FFB59A"
  on-primary-dark: "#55200A"
  primary-container-dark: "#71361E"
  on-primary-container-dark: "#FFDBCF"
  secondary-light: "#77574C"
  secondary-dark: "#E7BEAF"
  slate-blue-light: "#3E5676"
  on-slate-blue-light: "#FFFFFF"
  slate-blue-container-light: "#D5E3FF"
  on-slate-blue-container-light: "#0C1C33"
  slate-blue-dark: "#B5C8E8"
  on-slate-blue-dark: "#20334F"
  slate-blue-container-dark: "#364A67"
  on-slate-blue-container-dark: "#D5E3FF"
  surface-light: "#FAF8F5"
  surface-dim-light: "#DEDAD5"
  surface-bright-light: "#FAF8F5"
  surface-lowest-light: "#FFFFFF"
  surface-low-light: "#F4F1ED"
  surface-container-light: "#EEEBE7"
  surface-high-light: "#E8E5E1"
  surface-highest-light: "#E2DFDB"
  surface-dark: "#19191B"
  surface-dim-dark: "#131315"
  surface-bright-dark: "#3B3B3E"
  surface-lowest-dark: "#101012"
  surface-low-dark: "#202023"
  surface-container-dark: "#252528"
  surface-high-dark: "#2E2E31"
  surface-highest-dark: "#39393C"
  on-surface-light: "#231A16"
  on-surface-dark: "#F1DFD9"
  on-surface-variant-light: "#53433E"
  on-surface-variant-dark: "#D8C2BB"
  outline-light: "#85736D"
  outline-dark: "#A08D86"
  outline-variant-light: "#D8C2BB"
  outline-variant-dark: "#53433E"
  sun: "#FFC857"
  moon: "#ADD8FF"
  galactic-center: "#D4ADFF"
  celestial-label-background: "#16232B"
typography:
  title:
    fontFamily: "Source Sans 3"
    fontWeight: 600
  body:
    fontFamily: "Source Sans 3"
  label:
    fontFamily: "Source Sans 3"
rounded:
  celestial-label: "8px"
spacing:
  tight: "4px"
  compact: "8px"
  control: "12px"
  section: "16px"
  page-bottom: "24px"
components:
  celestial-label:
    backgroundColor: "{colors.celestial-label-background}"
    rounded: "{rounded.celestial-label}"
    padding: "6px"
  camera-marker-dark:
    backgroundColor: "{colors.primary-container-dark}"
    textColor: "{colors.on-primary-container-dark}"
    width: "48px"
    height: "48px"
  direction-marker-dark:
    backgroundColor: "{colors.primary-dark}"
    textColor: "{colors.on-primary-dark}"
    width: "48px"
    height: "48px"
---

# Design System: PhotoSim

## Overview

**Creative North Star: "The Scouting Desk"**

A precise, calm, practical workspace for photographic planning. The map and photographic preview are the working material; navigation and controls provide a quiet frame. Copper identifies interaction, graphite and warm ivory organize surfaces, and slate blue supplies a restrained cool counterpoint.

Controls feel precise and restrained, using familiar Material 3 shapes and states. Quiet tonal layers establish depth; menus and dialogs retain standard Material elevation. This is an extraction of the implemented interface, not a new visual direction.

**Key Characteristics:**
- Canvas-first workspace with progressive disclosure of technical controls.
- Copper accents, Graphite dark surfaces, Warm Ivory light surfaces, Slate Blue tertiary accents.
- Source Sans 3 throughout, with semibold section titles.
- Native Material 3 interaction, adapted to window size.

Source of truth: `lib/app/app.dart` supplies the theme; `lib/ui/` supplies component usage. The frontmatter records current shared values. Flutter dimensions are logical pixels; CSS units here are a portable documentation representation, not a replacement Flutter theme. Seed-generated roles can change with Flutter's Material implementation: regenerate this document after changing the seed or SDK color generation.

`.impeccable/design.json` extends this document with responsive thresholds, narrative and self-contained HTML/CSS previews. Those previews illustrate the native component families in the desktop dark palette; they are not pixel-identical Flutter controls or a shipped web interface. Its synthesized OKLCH ramps are panel visualization aids, not additional application tokens. Native Material defaults and behavior remain authoritative.

## Colors

### Primary

**Copper** is the seed-generated interaction family. Use the active theme's `primary`/`onPrimary` pair for actions and selection; use `primaryContainer`/`onPrimaryContainer` for quieter containers such as the camera marker. The seed itself is not the rendered primary color.

### Secondary

The generated secondary family is a muted copper-brown companion. Keep it subordinate to the primary and use matching `onSecondary` roles from the theme rather than inventing foreground colors.

### Tertiary

**Slate Blue** is the explicitly supplied tertiary family. Use it as the cool secondary emphasis, not as a replacement for the celestial Moon color.

### Neutral

**Graphite** forms the dark workspace; **Warm Ivory** forms the light workspace. Apply `surface`, container, foreground, outline and divider roles semantically. Main surfaces are almost neutral, while generated text and outline roles retain a subtle warm cast.

**The Paired Roles Rule.** Match backgrounds with their corresponding `on…` foregrounds. Existing theme tests require at least 4.5:1 contrast for their tested text-role pairs in both themes.

**The Scene Is Not Chrome Rule.** No green UI accents. Preserve natural map and terrain colors, celestial colors and rendered scene lighting; do not recolor geographic data to fit the interface palette.

Sun, Moon and Galactic center retain their distinct semantic colors and dark label background. The aligned level indicator is Flutter `Colors.lightBlueAccent`; the unaligned state is `Colors.amber`. Neither is a new primary palette.

## Typography

Source Sans 3 is the shared family, bundled locally in Regular, Medium, Semibold and Bold weights. Do not introduce remote font loading or a separate display family.

- **Title:** Material `titleLarge`, `titleMedium` and `titleSmall`, explicitly semibold (600).
- **Body:** Material body roles for settings, supporting information and readouts.
- **Label:** Material label roles for controls and navigation; small body text for attribution and compact supporting information.

Size, line height and tracking inherit from Flutter's Material typography and device text scaling; the app does not define a separate fixed type scale. Use `Theme.of(context).textTheme` rather than freezing framework-resolved values into widgets.

## Layout

The canvas expands into available space. Navigation, inspector and timeline surround it rather than competing with it. Window size, not device labels, determines layout:

- Below 600 logical pixels wide: compact bottom navigation.
- From 600 wide: labeled navigation rail with a thin vertical divider.
- From 1000 wide: optional docked camera inspector, 310 logical pixels wide.
- Below docking width: camera controls open in an end drawer, up to 400 wide, using full width below that.
- Timeline is compact below 600 wide or 600 high; short windows scroll timeline details to preserve canvas space.
- Clean preview hides navigation and editing chrome.

Observed spacing repeats 4, 8, 12 and 16 logical pixels, with 24 at settings-page bottoms. Inspector list padding is 8; section headers use 12 horizontal padding; expanded contents use 16 horizontal/bottom and 4 top. These are observed conventions, not an enforced global spacing API.

Android follows system light/dark appearance; the current non-Android shell selects dark mode. Preserve the established Linux workflow. Respect safe areas, scrolling and text scaling; do not force desktop density onto compact controls.

## Elevation & Depth

Quiet tonal layers separate workspace, inspector and transient information. Thin Material dividers remain useful structural boundaries. Standard Material cards, menus, drawers and dialogs retain framework elevation and overlays; the app has no custom shared shadow or motion scale. Do not invent a CSS-style shadow system or decorative floating panels.

## Shapes

Keep Material 3's inherited button, segmented-control, card, drawer and dialog silhouettes. The shared input decoration uses `OutlineInputBorder`; it does not override the framework's corner defaults. Map camera and direction controls are circular (48 logical pixels square). Celestial labels use gently curved corners (8 logical pixels) and compact internal padding (6 logical pixels).

## Components

### Buttons

Use `FilledButton` for primary commitments, `OutlinedButton` for secondary actions and `TextButton`/`IconButton` for quieter actions. Keep framework shapes, minimum interaction sizes, disabled appearance, hover, focus and pressed feedback. Icon-only actions retain tooltips or semantic labels.

### Segmented controls

Use `SegmentedButton` for choices such as sensor format and orientation. The inspector suppresses selected check icons; selected fill, borders and labels carry state. Do not replace these with decorative chips; there is no shared custom chip system.

### Cards / Containers

Use Material cards for contextual information, including the dismissible map guide. That guide uses 12 logical pixels of padding and a maximum width of 480. Use surface roles and framework elevation rather than independent hardcoded panel colors.

### Inputs / Fields

Outlined Material fields expose units, validation and native focus/error/disabled states. Numeric controls pair exact entry with sliders where already implemented. Preserve validation and do not signal errors by color alone.

### Navigation

The four destinations are Map, 3D Preview, Calendar and Export. Compact navigation uses a bottom bar; larger windows use a labeled rail. Material selected indicators, filled selected icons and text labels work together. Keep selection visible without relying on color alone.

### Camera inspector

Expandable, icon-labeled sections progressively disclose optics, position, terrain, exposure and related settings. Use semibold theme titles and consistent padding. Preserve scrolling and remembered expansion state.

### Map and timeline

The camera marker uses the primary container; the direction handle uses primary. The field-of-view wedge uses primary at 20% opacity with a primary border. Celestial bearings retain distinct colors and labeled altitude readouts. Provider attribution remains visible.

The timeline combines a scrubber with explicit local date/time, UTC context and astronomy readouts. Preserve units, timezone labels and compact behavior; do not reduce scientific readouts to unlabeled color badges.

## Do's and Don'ts

### Do:
- **Do** keep the map and preview visually primary.
- **Do** use semantic theme roles and matching foreground/background pairs in both themes.
- **Do** preserve Material interaction feedback, accessible labels and device text scaling.
- **Do** retain geographic attribution, explicit units and local/UTC time context.
- **Do** reuse native Material components before introducing custom controls.

### Don't:
- **Don't** reintroduce green UI accents or recolor natural geographic content to match the theme.
- **Don't** use the copper seed directly where the active theme's primary role belongs.
- **Don't** replace quiet tonal layering with decorative shadows, gradients or glass effects.
- **Don't** freeze framework typography or component defaults into an unrelated parallel design system.
- **Don't** treat approximate scene rendering as calibrated photographic evidence.
