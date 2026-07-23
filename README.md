# IPTV Player

A Windows desktop IPTV client for **subscriptions you already have**, built
with Flutter. Connects to Xtream Codes panels or loads M3U/M3U8 playlists
(URL or local file).

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
  keyboard shortcuts, fullscreen, Picture-in-Picture, channel zapping
- **Live TV** — EPG now/next + full grid, catch-up/timeshift on channels
  with an archive, resume last channel, radio visualizer
- **Library** — instant offline-first Home dashboard with customizable
  rails, search over a local index (optionally including cast/director/
  genre), genre browsing, favorites, watchlist, watch history, recently added
- **Offline** — VOD downloads with resume and speed controls
- **Parental controls** — PIN-locked categories and items
- **App** — 13 languages incl. full RTL, themes/accents/fonts, settings
  backup, tray mode with background audio, external-player hand-off (VLC)

See [CHANGELOG.md](CHANGELOG.md) for release notes and
[POLICY.md](POLICY.md) for the project's content policy — including the
features that will never be built.

## Install (Windows)

1. Download the latest `iptv_player-<version>-windows-x64.zip` from
   [Releases](../../releases).
2. Extract it anywhere and run `iptv_player.exe`.

> **"Windows protected your PC"?** The app is open-source but not
> code-signed (certificates cost money this donation-funded project doesn't
> spend). Click **More info → Run anyway**, or build it from source yourself.

If the app fails to start with a missing-DLL error, install the
[Microsoft Visual C++ Redistributable (x64)](https://aka.ms/vs/17/release/vc_redist.x64.exe).

## Privacy

**No telemetry.** Nothing about what you watch, search, download, or connect
to ever leaves your device. The app talks only to the panel/playlist URLs you
give it. Credentials are stored with OS-level secure storage (DPAPI);
posters and metadata are cached locally for speed and offline use.

## Building from source

This is a standard Flutter desktop project:

```
flutter pub get
flutter build windows --release
```

The runnable app lands in `build\windows\x64\runner\Release\`. Or use
`tool\package_release.ps1` to produce the distributable zip. See the
[Flutter documentation](https://docs.flutter.dev/) if you're new to Flutter.

## License

MIT — see [LICENSE](LICENSE). Bundled fonts are under the SIL Open Font
License 1.1 (see `assets/fonts/FONT-LICENSES.md`).
