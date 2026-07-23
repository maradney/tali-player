# Changelog

All notable changes to this project are documented here. The format loosely
follows [Keep a Changelog](https://keepachangelog.com/); versions follow
[Semantic Versioning](https://semver.org/).

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

[Unreleased]: https://github.com/Maradney/iptv_player/compare/v0.1.0...HEAD
