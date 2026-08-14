# Changelog

All notable changes to this project are documented here. The format loosely
follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added
- **Android support.** The app builds, runs, and exports correctly on Android
  7.0 (API 24) and newer, with per-ABI release APKs and a documented signing
  setup (see `tool/ANDROID_SIGNING.md`)
- Phone-shaped layouts across the shell and every content screen, not just the
  navigation chrome
- Player behaviour suited to a handset: screen kept awake, immersive
  fullscreen, auto-rotate to landscape on fullscreen, back gesture unwinds one
  layer at a time
- App data stays on the device — cloud backup and device-to-device transfer are
  disabled, so credentials never leave the phone

### Changed
- **The app is now called Tali** (تالي) everywhere it is user-visible, with its
  own icon and a permanent application ID of `io.github.maradney.tali`
- The export button is named after whatever actually opens on the current
  platform
- A TLS handshake failure is explained in words instead of printing OpenSSL's
  raw error code

### Fixed
- Catalogue sections are only replaced when their fetch fully succeeded. A
  partly-failed sync used to wipe a working index and stamp the emptiness as
  current, stranding Live and Movies at "0 items / Updated never"
- The Search tab bar could show three different answers at once to "which tab
  am I on" — indicator, label, and body each followed a different source
- The selected episode's highlight no longer smears over the series
  description while scrolling
- Posters cached in an unusable state are re-fetched instead of staying broken
- The resume point is protected from being reset to zero when a video fails to
  load; skip presses are batched into one seek instead of stacking buffers
- Long descriptions and cut-off titles are now reachable
- The app-bar scroll tint no longer leaks between tabs
- Sign-in form and player controls no longer overflow on a phone in landscape

## 0.1.0 — first public release

A Windows desktop IPTV client for subscriptions you already have. Highlights:

### Sources
- Xtream Codes panels: Live TV, Movies, Series, EPG, account status
- M3U/M3U8 playlists (URL or local file) with optional XMLTV EPG
- Multiple playlists per profile, switchable; credentials in OS secure storage

### Watching
- Player built on libmpv: subtitles, audio tracks, video quality selection,
  playback speed (VOD), aspect-ratio modes, keyboard shortcuts (+ help overlay)
- Live channel zapping (prev/next in place), resume last channel
- Catch-up / timeshift for channels whose panel advertises an archive
- Radio / audio-only visualizer instead of a black screen
- Fullscreen, Picture-in-Picture (mini always-on-top window), and an opt-in
  "keep running in the tray" mode with background audio
- External player hand-off (VLC on Windows, opt-in)

### Library
- Home dashboard: hero "pick up where you left off" banner, customizable
  rails (continue watching / watchlist / recently added / downloads /
  favorites / any category), all from local data — opens instantly, offline
- Search over a local SQLite index; optional enhanced search (cast, director,
  genre) via an opt-in background crawl; genre browsing
- Favorites (reorderable), Watchlist, Watch History, Recently Added
- Offline VOD downloads with resume, parallelism, and speed-limit controls
- Parental controls: PIN-locked categories and items
- Per-user profiles with fully isolated data, including **kids profiles** — a
  default-deny content allowlist (the profile shows only the categories a
  parent permits) with a guided setup and a reminder to PIN the other profiles.
  Profile management is behind a parent's PIN while a kids profile is signed in

### App
- 13 languages incl. full RTL (Arabic, Persian, Urdu); bundled OFL fonts
- Light/dark/system theme, accent presets, grid density, font choice
- Settings backup export/import (per profile)
- Diagnostics screen; no telemetry of any kind
