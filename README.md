<p align="center">
  <img src="design/tali-logo.png" alt="Tali" width="132" height="132">
</p>

<h1 align="center">Tali</h1>

<p align="center">
  <strong>تالي</strong> — Arabic for <em>next</em>.<br>
  An IPTV player for subscriptions you already have.
</p>

<p align="center">
  Windows &nbsp;·&nbsp; Android &nbsp;·&nbsp; MIT &nbsp;·&nbsp; No telemetry
</p>

---

Tali is a desktop and mobile IPTV client built with Flutter. It connects to
Xtream Codes panels or loads M3U/M3U8 playlists (URL or local file), keeps a
local index of your catalogue so browsing is instant and works offline, and
plays through libmpv so unusual streams and codecs behave.

## What this is — and isn't

This is a **generic player app**. It does not provide, host, sell, bundle,
or index any TV channels, movies, or series, and it ships with **no content
sources of any kind** — no default servers, no demo playlists, no provider
directory. To use it, you supply the credentials or playlist of an IPTV
subscription you already have.

The app is not affiliated with, and does not endorse, any specific content
provider or panel operator. **You are responsible for the legality of any
subscription or playlist you connect it to.** See [POLICY.md](POLICY.md).

## Features

- **Sources** — Xtream Codes panels and M3U/M3U8 playlists (with optional
  XMLTV EPG); multiple playlists, switchable; per-user profiles with fully
  isolated data
- **Player** — libmpv-based (handles raw TS/HLS and unusual codecs);
  subtitle/audio/quality track selection, playback speed, aspect modes,
  fullscreen, channel zapping
- **Live TV** — EPG now/next + full grid, catch-up/timeshift on channels
  with an archive, resume last channel, radio visualizer
- **Library** — offline-first Home dashboard with customizable rails, search
  over a local index (optionally including cast/director/genre), genre
  browsing, favorites, watchlist, watch history, recently added
- **Offline** — VOD downloads with resume and speed controls
- **Parental controls** — PIN-locked categories and items, plus **kids
  profiles**: a default-deny allowlist where the profile shows only the
  categories a parent permits
- **App** — 13 languages including full RTL (Arabic, Persian, Urdu),
  themes/accents/fonts, settings backup, diagnostics screen

A few things are necessarily platform-specific:

| | Windows | Android |
|---|---|---|
| Keyboard shortcuts + help overlay | ✅ | — |
| Picture-in-Picture (always-on-top mini window) | ✅ | — |
| Tray mode with background audio | ✅ | — |
| External player hand-off (VLC) | ✅ | — |
| Immersive fullscreen, auto-rotate, screen kept awake | — | ✅ |

## Status

Version **0.1.0**. Windows is the mature target and has been through a full
release pass. The Android port is newer — it builds, runs, and is being
verified on real hardware; expect rougher edges there. See
[CHANGELOG.md](CHANGELOG.md) for what has landed and [POLICY.md](POLICY.md)
for the project's content policy, including the features that will never be
built.

## Install

### Windows

1. Download the latest `tali-<version>-windows-x64.zip` from
   [Releases](../../releases).
2. Extract it anywhere and run `tali.exe`.

> **"Windows protected your PC"?** The app is open-source but not
> code-signed (certificates cost money this donation-funded project doesn't
> spend). Click **More info → Run anyway**, or build it from source yourself.

If the app fails to start with a missing-DLL error, install the
[Microsoft Visual C++ Redistributable (x64)](https://aka.ms/vs/17/release/vc_redist.x64.exe).

### Android

Requires **Android 7.0 (API 24)** or newer. Download the APK matching your
phone from [Releases](../../releases) and allow installation from unknown
sources when prompted:

| APK | For |
|---|---|
| `app-arm64-v8a-release.apk` | Virtually every phone sold in the last decade |
| `app-armeabi-v7a-release.apk` | Older 32-bit devices |
| `app-x86_64-release.apk` | Emulators |

The per-ABI split exists because a universal APK carries every architecture's
copy of libmpv and is roughly twice the size any one phone needs.

## Privacy

**No telemetry.** Nothing about what you watch, search, download, or connect
to ever leaves your device. The app talks only to the panel/playlist URLs you
give it. Credentials are stored with OS-level secure storage (DPAPI on
Windows, the Android Keystore on Android); posters and metadata are cached
locally for speed and offline use. Fonts are bundled rather than fetched, so
the app makes no third-party requests at all.

## Building from source

A standard Flutter project — built against **Flutter 3.44** (Dart SDK
`>=3.3.0 <4.0.0`).

```
flutter pub get
flutter build windows --release
```

The runnable app lands in `build\windows\x64\runner\Release\`. Or run
`tool\package_release.ps1` to produce the distributable zip, which also
bundles the VC++ runtime DLLs.

For Android:

```
flutter build apk --release --split-per-abi
```

Release builds are signed with a key you create yourself — see
[tool/ANDROID_SIGNING.md](tool/ANDROID_SIGNING.md). Without one the build
still succeeds, falling back to the debug key with a warning, so it is worth
verifying rather than assuming.

**Supported targets are Windows and Android.** The `ios/`, `macos/` and
`linux/` directories are Flutter's generated scaffolding; they are not built,
tested, or supported.

## Repository layout

```
lib/            app source
  data/         API clients, database, models, services
  features/     one directory per screen or feature area
  l10n/         ARB translation sources (13 locales)
test/           633 tests — unit, widget, and golden-ish pixel checks
android/ windows/   platform projects
design/         logo and app-icon sources (SVG masters + exports)
tool/           release packaging and signing docs
```

Run the suite with `flutter test` and the linter with `flutter analyze`.

## License

MIT — see [LICENSE](LICENSE). Bundled fonts are under the SIL Open Font
License 1.1 (see `assets/fonts/FONT-LICENSES.md`). The Tali wordmark is set
in [Aref Ruqaa](https://fonts.google.com/specimen/Aref+Ruqaa), also OFL.
