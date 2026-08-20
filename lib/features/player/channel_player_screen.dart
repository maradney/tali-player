import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/api/credential_redaction.dart';
import '../../data/models/account.dart';
import '../../data/models/channel.dart';
import '../../data/models/epg_program.dart';
import '../../data/models/favorite_item.dart';
import '../../data/models/download_item.dart';
import '../../data/models/playback_progress.dart';
import '../../data/models/series_info.dart';
import '../../data/models/watch_history_entry.dart';
import '../../data/services/download_service.dart';
import '../../data/services/external_player.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../../platform_capabilities.dart';
import '../common/pin_dialogs.dart';
import '../series/episode_navigator.dart';
import 'shortcuts_help.dart';
import 'audio_only_visualizer.dart';
import 'fullscreen_orientation.dart';
import 'resume_guard.dart';
import 'screen_awake.dart';
import 'seek_accumulator.dart';
import 'stream_failure.dart';
import 'track_labels.dart';
import 'video_fit.dart';

/// Below this, resuming isn't worth prompting for - the user barely
/// started watching.
const _resumeThreshold = Duration(seconds: 10);

/// Above this fraction of the total runtime, treat the item as finished
/// rather than "in progress" - avoids re-prompting to resume 30 seconds
/// of credits.
const _finishedFraction = 0.95;

/// Localized menu label for a video-fit mode. Mirrors [videoFitLabel] (kept
/// in English for its unit test) but pulled through the l10n strings.
String _videoFitLabel(BoxFit fit, AppLocalizations l) {
  switch (fit) {
    case BoxFit.cover:
      return l.fitCover;
    case BoxFit.fill:
      return l.fitFill;
    case BoxFit.contain:
    default:
      return l.fitContain;
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Generic playback screen - takes a title (for the app bar) and a
/// direct stream URL, and plays it. Works for live channels, movies,
/// and episodes alike since they're all just a URL to media_kit.
///
/// [epgFuture] is optional - only live channels have EPG data, so
/// movies/episodes can simply omit it and no strip is shown.
/// [favoriteItem] is optional - when provided, shows a star toggle in
/// the app bar so you can favorite/unfavorite while watching.
/// [playbackRef] is optional - when provided (movies/episodes, not live
/// channels), position is periodically saved via PlaybackService, and a
/// "continue watching?" prompt shows if there's a prior saved position.
/// [seriesName] is optional and only meaningful alongside an episode
/// [playbackRef] - it's the display name used for that episode's Watch
/// History row (the series, not "Series - Episode Title"), since that's
/// what the history screen jumps back into.
///
/// [channels] + [account] enable live-TV "zapping": when a channel list and
/// account are supplied, the player shows prev/next controls (and PageUp/
/// PageDown keys) that swap streams in place - the current channel starts at
/// [channelIndex]. Zapping is live-only; movies/episodes omit these.
/// A common browser User-Agent. Many public IPTV/HLS servers reject the media
/// player's default agent (libmpv) with a 403, so M3U live streams send this
/// unless the playlist entry specified its own via `#EXTVLCOPT`.
const _kIptvUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// The HTTP headers to play [channel] with. For M3U it defaults a browser
/// [User-Agent] (overridable by the channel's own headers); for Xtream it's
/// just whatever the channel carries (normally none).
Map<String, String>? iptvStreamHeaders(Channel channel, {required bool isM3u}) {
  if (!isM3u) return channel.headers;
  return {'User-Agent': _kIptvUserAgent, ...?channel.headers};
}

/// The HTTP headers for M3U VOD playback (movies/episodes): the same default
/// browser [User-Agent] live uses — M3U VOD entries carry no per-entry
/// `#EXTVLCOPT` today, so the UA is all there is. Null for Xtream (whose
/// panels expect their own URLs to be fetched plainly) and for local files.
Map<String, String>? iptvVodHeaders({required bool isM3u}) =>
    isM3u ? {'User-Agent': _kIptvUserAgent} : null;

class ChannelPlayerScreen extends StatefulWidget {
  final String title;
  final String streamUrl;
  final Future<List<EpgProgram>>? epgFuture;
  final FavoriteItem? favoriteItem;
  final PlaybackRef? playbackRef;
  final String? seriesName;
  final List<Channel>? channels;
  final int channelIndex;
  final Account? account;

  /// HTTP headers for the initial stream (M3U channels that need a specific
  /// `User-Agent`/`Referer`). Null for Xtream.
  final Map<String, String>? httpHeaders;

  /// Treat the stream as seekable on-demand content even without a
  /// [playbackRef] — catch-up/timeshift replays are fixed past footage
  /// (pause/seek work; the live rejoin-at-edge logic must NOT apply), but
  /// carry no resume position.
  final bool seekable;

  /// Every season of the series this episode belongs to, so the player can
  /// move to the next/previous episode itself rather than being closed and
  /// reopened per episode. Null for anything that is not an episode.
  ///
  /// Requires [account] as well: the URL for another episode has to be built
  /// (or resolved to a downloaded file) at the moment it is played, since the
  /// caller only ever resolved the one it opened with.
  final SeriesInfo? seriesInfo;

  /// The series' own name, used to rebuild the title when the episode
  /// changes. [seriesName] serves the same purpose for watch history.
  final String? seriesDisplayName;

  const ChannelPlayerScreen({
    super.key,
    required this.title,
    required this.streamUrl,
    this.epgFuture,
    this.favoriteItem,
    this.playbackRef,
    this.seriesName,
    this.channels,
    this.channelIndex = 0,
    this.account,
    this.httpHeaders,
    this.seekable = false,
    this.seriesInfo,
    this.seriesDisplayName,
  });

  @override
  State<ChannelPlayerScreen> createState() => _ChannelPlayerScreenState();
}

class _ChannelPlayerScreenState extends State<ChannelPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  Timer? _progressTimer;

  // The currently-tuned channel's content. These start from the widget's
  // values and are swapped in place when zapping to another live channel,
  // so the screen doesn't push a new player per channel.
  // Bound only when an account is supplied (i.e. live channels that can zap);
  // movies/episodes open with a direct URL and never touch this.
  late final _source =
      widget.account == null ? null : MediaSource.forAccount(widget.account!);
  late String _title;
  late String _streamUrl;
  Map<String, String>? _headers;
  late int _channelIndex;
  Future<List<EpgProgram>>? _epgFuture;
  FavoriteItem? _favoriteItem;

  bool get _canZap =>
      widget.channels != null &&
      widget.channels!.length > 1 &&
      widget.account != null;

  // ---- series episode navigation ----

  /// Where in the series we are. Both are null unless the player was opened
  /// with a [ChannelPlayerScreen.seriesInfo] that actually contains the
  /// episode it was asked to play.
  EpisodeNavigator? _navigator;
  EpisodeCursor? _cursor;

  /// Rebuilt on every episode change, so progress, history and the resume
  /// guard all follow the episode actually on screen rather than the one the
  /// screen was opened with.
  PlaybackRef? _playbackRef;

  /// Ticks down to the next episode after one finishes. Non-null only while
  /// the countdown overlay is showing.
  Timer? _autoplayTimer;
  int _autoplaySecondsLeft = 0;

  /// How long the viewer gets to stop the next episode. Long enough to read
  /// and reach, short enough not to feel like a stall.
  static const _autoplayCountdown = 8;

  bool get _isSeries => _navigator != null && _cursor != null;
  bool get _hasNextEpisode => _isSeries && _navigator!.hasNext(_cursor!);
  bool get _hasPreviousEpisode =>
      _isSeries && _navigator!.hasPrevious(_cursor!);

  // Audio/subtitle tracks the media exposes, and which are currently active.
  // Populated from the player's tracks/track streams once media loads.
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  List<VideoTrack> _videoTracks = const [];
  String? _currentAudioId;
  String? _currentSubtitleId;
  String? _currentVideoId;

  bool _isPlaying = false;
  String? _error;

  // Connecting/buffering feedback: [_buffering] drives a spinner overlay
  // until the first frame plays. If nothing has started within [_openTimeout]
  // the stream's server is treated as unresponsive and an error is shown -
  // otherwise an unreachable stream just sits on a black screen forever.
  bool _buffering = true;
  bool _started = false;
  Timer? _startTimeoutTimer;
  static const _openTimeout = Duration(seconds: 20);

  // Stops a stream that stalled or failed near zero from overwriting a real
  // resume point with its own failure. See [ResumeGuard].
  ResumeGuard? _resumeGuard;

  // Collapses a burst of skip-button presses into one seek. See
  // [SeekAccumulator].
  late final SeekAccumulator _seekAccumulator = SeekAccumulator(
    onSeek: (total) => unawaited(_applySeekDelta(total)),
  );

  // Live streams drop transiently; recover silently up to this many times (like
  // VLC) before surfacing an error, so a blip doesn't force reopening the
  // channel. Reset whenever playback (re)starts or the user switches channel.
  static const _maxLiveRetries = 5;
  int _liveRetries = 0;

  double _volume = 100;
  bool _muted = false;
  double _volumeBeforeMute = 100;
  bool _isFullscreen = false;

  /// Whether the window was maximized when fullscreen was entered, so leaving
  /// fullscreen can put it back instead of leaving a small floating window.
  bool _wasMaximizedBeforeFullscreen = false;

  // How the video fills its box (Fit / Fill-crop / Stretch). Session-local:
  // resets to "Fit" each time the player is opened, since the right mode
  // depends on the specific stream's framing.
  BoxFit _videoFit = BoxFit.contain;

  // Seek and speed control only make sense for on-demand content - a live
  // stream has no fixed duration to seek within and no "faster/slower",
  // it's whatever the channel is broadcasting right now. A [playbackRef] is
  // exactly what on-demand content (movies/episodes) carries and live
  // channels never do, so it's the reliable signal for "this is VOD" -
  // regardless of whether the caller also supplied EPG data. (Deriving this
  // from [epgFuture] instead was fragile: a live channel opened without an
  // epgFuture - e.g. from Favorites - was wrongly treated as seekable VOD.)
  // [seekable] extends this to catch-up/timeshift replays, which behave like
  // VOD (fixed past footage) but never track a resume position.
  bool get _isVod => _playbackRef != null || widget.seekable;

  /// A playing stream with audio but no real video track — radio. Drives the
  /// animated visualizer overlay so the screen isn't just black. Only ever
  /// true once playback started AND the track lists are populated (before
  /// that, an empty video list just means "don't know yet").
  bool get _audioOnly {
    if (!_started) return false;
    bool real(String id) => id != 'auto' && id != 'no';
    return _audioTracks.any((t) => real(t.id)) &&
        !_videoTracks.any((t) => real(t.id));
  }

  double _playbackRate = 1.0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  // Non-null only while the user is actively dragging the seek bar - shows
  // the drag target immediately instead of snapping back to the last known
  // position stream value until the seek completes.
  double? _seekDragValue;

  // Owns keyboard shortcuts for the whole screen - the seek bar/volume
  // sliders and icon buttons are excluded from focus (see build()) so they
  // never intercept arrow keys/space themselves.
  final FocusNode _focusNode = FocusNode();

  // Custom controls overlay stays visible while paused, and while playing
  // auto-hides a few seconds after the last mouse move/tap so it doesn't
  // sit on top of the video.
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  // When external playback is on, we hand the stream off to VLC and skip the
  // whole media_kit pipeline. [_externalLaunchFailed] flips true if the
  // external process couldn't be started (e.g. a stale path).
  bool _external = false;
  bool _externalLaunchFailed = false;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _streamUrl = widget.streamUrl;
    _headers = widget.httpHeaders;
    _channelIndex = widget.channelIndex;
    _epgFuture = widget.epgFuture;
    _favoriteItem = widget.favoriteItem;
    _playbackRef = widget.playbackRef;

    // Episode navigation needs three things at once: the season list, an
    // account to build URLs from, and the current episode actually being
    // present in that list. Missing any of them simply means no next/previous
    // controls, rather than a half-working pair of buttons.
    final info = widget.seriesInfo;
    final ref = _playbackRef;
    if (info != null && widget.account != null && ref?.type == 'episode') {
      final nav = EpisodeNavigator(info.seasons);
      final at = nav.locate(ref!.id);
      if (at != null) {
        _navigator = nav;
        _cursor = at;
      }
    }

    // Hand off to the external player instead of building the internal one.
    // Still record watch history (that's URL-independent); everything below
    // is internal-player-only and stays uninitialised.
    if (ExternalPlayer.isSupported &&
        SettingsService.instance.useExternalPlayer) {
      _external = true;
      _scheduleRecordHistory();
      _launchExternal();
      return;
    }

    _player = Player();
    _controller = VideoController(_player);

    _player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) _markStarted();
      // Don't let the display sleep in the middle of a film; released again as
      // soon as playback stops, so a paused or dead stream can't keep the
      // screen lit. (_external is false here - that path returns above.)
      ScreenAwake.set(
        shouldKeepScreenAwake(playing: playing, external: _external),
      );
      setState(() {
        _isPlaying = playing;
        if (!playing) _controlsVisible = true;
      });
      if (playing) {
        _scheduleHideControls();
      } else {
        _hideControlsTimer?.cancel();
      }
    });

    // Spinner overlay while the stream is opening/rebuffering.
    // End of the episode. media_kit also emits this for live streams that
    // drop, so _onPlaybackCompleted checks it is actually a series first.
    _player.stream.completed.listen((completed) {
      if (!mounted || !completed) return;
      _onPlaybackCompleted();
    });

    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _buffering = buffering);
    });

    // Surface stream errors (bad URL, provider down, unsupported codec)
    // instead of silently showing a black screen. A real error supersedes the
    // "still connecting" timeout.
    _player.stream.error.listen((error) {
      if (!mounted) return;
      _startTimeoutTimer?.cancel();
      // A live channel that had been playing just dropped — reopen it quietly
      // (like VLC would) instead of dumping the user to the error screen. VOD
      // errors, and live streams that never started, are shown immediately.
      if (!_isVod && _started && _liveRetries < _maxLiveRetries) {
        _liveRetries++;
        setState(() {
          _error = null;
          _buffering = true;
          _started = false;
        });
        Timer(const Duration(seconds: 2), () {
          if (mounted && _error == null && !_started) _openStream();
        });
        return;
      }
      setState(() {
        // mpv names the URL it failed to open, and an Xtream stream URL
        // carries the username/password as path segments - redact before this
        // ever reaches the screen (it's shown verbatim by the error overlay,
        // and stays up until _classifyFailure's probe returns).
        _error = redactCredentials(error);
        _buffering = false;
      });
      // Upgrade mpv's raw "Failed to open" to a plain-language reason when we
      // can tell (blocked / not found / unreachable).
      unawaited(_classifyFailure());
    });

    _player.stream.position.listen((position) {
      // Ignore position updates while dragging so the thumb doesn't jump
      // around under the user's finger/cursor.
      if (position > Duration.zero) _markStarted();
      // Tells the guard when a resume seek has actually landed, after which
      // ordinary saving resumes.
      _resumeGuard?.observe(position);
      if (!mounted || _seekDragValue != null) return;
      setState(() {
        // Advancing position means the picture is moving — definitely not
        // "connecting". Un-sticks the overlay if a buffering=false event was
        // missed around an error/recovery (the events can race our own state).
        if (_buffering && position > _position) _buffering = false;
        _position = position;
      });
    });
    _player.stream.duration.listen((duration) {
      // A known duration means the media loaded - counts as "started" even
      // while paused for the resume prompt, so the timeout doesn't false-fire.
      if (duration > Duration.zero) _markStarted();
      if (mounted) setState(() => _duration = duration);
    });

    // Available audio/subtitle tracks and the currently-selected ones - drive
    // the track pickers in the controls overlay.
    _player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() {
          _audioTracks = tracks.audio;
          _subtitleTracks = tracks.subtitle;
          _videoTracks = tracks.video;
        });
      }
    });
    _player.stream.track.listen((track) {
      if (mounted) {
        setState(() {
          _currentAudioId = track.audio.id;
          _currentSubtitleId = track.subtitle.id;
          _currentVideoId = track.video.id;
        });
      }
    });

    unawaited(_beginPlayback());
  }

  /// Configures the native player for resilient live streaming, *then* starts
  /// it — the reconnect options must be set before the media is opened.
  Future<void> _beginPlayback() async {
    await _configureForLiveStreams();
    if (!mounted) return;
    _openStream();
    _scheduleRecordHistory();

    final ref = _playbackRef;
    if (ref != null) {
      final saved = PlaybackService.instance.progressFor(ref.type, ref.id);
      // Built before the timer starts: its first tick can land while the
      // stream is still opening, which is exactly the case being guarded.
      _resumeGuard = ResumeGuard(savedPosition: saved?.position);
      _progressTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress(ref));
      if (saved != null && saved.position > _resumeThreshold) {
        _player.pause();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _promptResume(saved));
      }
    }
  }

  /// Makes the native (mpv/FFmpeg) player reconnect through the transient drops
  /// that live IPTV streams routinely have. Without this, mpv gives up after
  /// the first hiccup and the stream dies after a few minutes — whereas VLC
  /// reconnects on its own (why external playback stays up for hours).
  /// Best-effort and desktop-only (NativePlayer).
  Future<void> _configureForLiveStreams() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // FFmpeg HTTP options: reconnect on dropped/interrupted connections,
      // including non-seekable live streams, backing off up to 30s before
      // giving up — so a momentary CDN/segment blip doesn't end playback.
      await platform.setProperty('stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_delay_max=30');
      // Buffer ahead of the playhead so a dropped connection keeps playing
      // from cache while FFmpeg reconnects behind the scenes — that's what
      // makes recovery invisible instead of a visible cut. (For a true live
      // stream the readahead is bounded by what the server has published,
      // typically a few segments — enough to ride out a short reconnect.)
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('cache-secs', '30');
      await platform.setProperty('demuxer-readahead-secs', '10');
      await platform.setProperty('demuxer-max-bytes', '67108864'); // 64 MiB
      // Join live HLS at the NEWEST segment. FFmpeg's default is 3 segments
      // behind the edge, so a recovery rejoin would replay content that
      // already aired and read as "the stream restarted". Live must always
      // land on now — both on first open and on any rejoin.
      await platform.setProperty('demuxer-lavf-o', 'live_start_index=-1');
    } catch (_) {
      // Non-fatal — playback still works, just less resilient to drops.
    }
  }

  /// The stream produced something (playing, a position, or a known
  /// duration), so it did reach the server - cancel the unresponsive-server
  /// timeout.
  void _markStarted() {
    if (_started) return;
    _started = true;
    _liveRetries = 0; // a clean (re)start refills the recovery budget
    _startTimeoutTimer?.cancel();
  }

  void _openStream() {
    _player.open(Media(
      _streamUrl,
      httpHeaders: (_headers != null && _headers!.isNotEmpty) ? _headers : null,
    ));
    _startTimeoutTimer?.cancel();
    _startTimeoutTimer = Timer(_openTimeout, () {
      if (!mounted || _started || _error != null) return;
      setState(() {
        _buffering = false;
        _error = AppLocalizations.of(context)!.streamStartFailed;
      });
      // A stalled stream (no error, never started) — probe to explain why.
      unawaited(_classifyFailure());
    });
  }

  bool _classified = false;

  /// On a failed open, probe the URL so we can explain *why* in plain language
  /// (blocked / not found / unreachable) instead of mpv's raw "Failed to open".
  /// Reads only the first few KB — enough to sniff an anti-bot challenge page.
  Future<void> _classifyFailure() async {
    // One probe per failure, whichever path fires first.
    if (_classified) return;
    _classified = true;

    int? status;
    String? body;
    try {
      final res = await Dio().get<List<int>>(
        _streamUrl,
        options: Options(
          headers: {...?_headers, 'range': 'bytes=0-4095'},
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      status = res.statusCode;
      body = utf8.decode(res.data ?? const [], allowMalformed: true);
    } on DioException catch (e) {
      status = e.response?.statusCode;
    } catch (_) {
      // Leave status null → treated as unreachable.
    }
    if (!mounted || _started) return;

    final l = AppLocalizations.of(context)!;
    final friendly =
        switch (classifyStreamFailure(statusCode: status, bodySnippet: body)) {
      StreamFailureKind.blocked => l.streamBlocked,
      StreamFailureKind.notFound => l.streamNotFound,
      StreamFailureKind.unreachable => l.streamUnreachable,
      // Server answered but not a recognizable failure — keep the player's own
      // message (or the stall fallback).
      StreamFailureKind.unknown => _error ?? l.streamStartFailed,
    };
    setState(() => _error = friendly);
  }

  /// Hands the current stream to the configured external player. On failure
  /// (bad path, etc.) flips [_externalLaunchFailed] so the hand-off screen can
  /// offer to retry or point the user back to Settings.
  Future<void> _launchExternal() async {
    final ok = await ExternalPlayer.launch(
        SettingsService.instance.externalPlayerPath, _streamUrl);
    if (mounted && !ok) setState(() => _externalLaunchFailed = true);
  }

  /// Tunes to another channel in [widget.channels] (wrapping past the ends)
  /// and swaps the stream in place - the essence of live-TV zapping. A locked
  /// target channel still prompts for the PIN, like opening it from the list.
  /// Switches to [cursor]'s episode in place, the way [_zapBy] switches
  /// channel — pushing a route per episode would stack the whole season on
  /// the navigator and tear down the player each time.
  Future<void> _playEpisodeAt(EpisodeCursor cursor) async {
    final nav = _navigator;
    final account = widget.account;
    if (nav == null || account == null) return;
    final episode = nav.episodeAt(cursor);
    final season = nav.seasonAt(cursor);
    if (episode == null || season == null) return;

    _cancelAutoplay();
    // The episode being left keeps its position: the viewer may come back to
    // it, and Previous is one button away.
    final leaving = _playbackRef;
    if (leaving != null) _saveProgress(leaving);

    // Resolved per episode, not once: a downloaded episode must play from
    // disk even when the one before it streamed, and vice versa.
    final stored = _downloadedEpisode(episode.id);
    final localPath = stored == null
        ? null
        : DownloadService.instance.localPathFor(stored);
    final url = localPath ?? MediaSource.forAccount(account).episodeUrl(episode);

    final ref = PlaybackRef(
      type: 'episode',
      id: episode.id,
      seriesId: _playbackRef?.seriesId,
      seasonNumber: season.seasonNumber,
      episodeNum: episode.episodeNum,
      categoryId: _playbackRef?.categoryId,
    );

    if (!mounted) return;
    setState(() {
      _cursor = cursor;
      _playbackRef = ref;
      _title = '${widget.seriesDisplayName ?? widget.title} - ${episode.title}';
      _streamUrl = url;
      _headers =
          localPath != null ? null : iptvVodHeaders(isM3u: account.isM3u);
      _error = null;
      _buffering = true;
      _started = false;
      _classified = false;
      _audioTracks = const [];
      _subtitleTracks = const [];
      _videoTracks = const [];
    });

    // Rebuild the resume machinery around the new episode: a saved position
    // for *this* episode should be honoured, and the old episode's guard must
    // not veto it.
    _progressTimer?.cancel();
    final saved = PlaybackService.instance.progressFor(ref.type, ref.id);
    _resumeGuard = ResumeGuard(savedPosition: saved?.position);
    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress(ref));

    _openStream();
    _recordHistory();
  }

  /// The stored download record for an episode, or null if it isn't
  /// downloaded. Looked up rather than reconstructed: the on-disk filename is
  /// derived from fields only the real record has, so a fabricated stand-in
  /// would resolve to a path that does not exist.
  DownloadItem? _downloadedEpisode(String episodeId) {
    for (final item in DownloadService.instance.items) {
      if (item.type == 'episode' &&
          item.id == episodeId &&
          item.status == DownloadStatus.completed) {
        return item;
      }
    }
    return null;
  }

  Future<void> _goToEpisode(int delta) async {
    if (!_isSeries) return;
    final target = delta > 0
        ? _navigator!.next(_cursor!)
        : _navigator!.previous(_cursor!);
    if (target == null) return; // first of the series, or last — nothing to do
    await _playEpisodeAt(target);
  }

  /// Called when the stream reaches its end.
  void _onPlaybackCompleted() {
    if (!_isSeries) return;
    if (!SettingsService.instance.autoplayNextEpisode) return;
    // Season-bounded on purpose: finishing a season should let you stop.
    if (!_navigator!.shouldAutoplayAfter(_cursor!)) return;
    _startAutoplayCountdown();
  }

  void _startAutoplayCountdown() {
    _autoplayTimer?.cancel();
    setState(() => _autoplaySecondsLeft = _autoplayCountdown);
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_autoplaySecondsLeft <= 1) {
        t.cancel();
        _autoplayTimer = null;
        final next = _navigator!.nextInSeason(_cursor!);
        setState(() => _autoplaySecondsLeft = 0);
        if (next != null) _playEpisodeAt(next);
        return;
      }
      setState(() => _autoplaySecondsLeft--);
    });
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    if (_autoplaySecondsLeft != 0 && mounted) {
      setState(() => _autoplaySecondsLeft = 0);
    } else {
      _autoplaySecondsLeft = 0;
    }
  }

  Future<void> _zapBy(int delta) async {
    if (!_canZap) return;
    final channels = widget.channels!;
    // Dart's % returns a non-negative result for a positive divisor, so this
    // wraps correctly in both directions.
    final index = (_channelIndex + delta) % channels.length;
    final channel = channels[index];
    if (PinLockService.instance.isItemLocked('live', channel.streamId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToWatch(channel.name));
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() {
      _channelIndex = index;
      _title = channel.name;
      _streamUrl = _source!.liveUrl(channel);
      _headers =
          iptvStreamHeaders(channel, isM3u: widget.account?.isM3u ?? false);
      _epgFuture = _source.getShortEpg(channel.streamId);
      _favoriteItem = FavoriteItem(
        type: 'live',
        id: channel.streamId,
        name: channel.name,
        imageUrl: channel.logoUrl,
        categoryId: channel.categoryId,
      );
      _error = null;
      _buffering = true;
      _started = false;
      _classified = false;
      _liveRetries = 0;
      // The new channel exposes its own tracks; clear the old ones so the
      // pickers don't briefly show the previous channel's tracks.
      _audioTracks = const [];
      _subtitleTracks = const [];
      _videoTracks = const [];
    });
    _openStream();
    _recordHistory();
  }

  /// Re-attempts a stream that failed or timed out (the overlay's Retry).
  void _retry() {
    setState(() {
      _error = null;
      _buffering = true;
      _started = false;
      _classified = false;
      _liveRetries = 0;
    });
    _openStream();
  }

  /// Logs this open to Watch History, separate from PlaybackService's
  /// resume-position tracking - recorded once per screen open, right when
  /// playback starts, not on every progress tick like [_saveProgress].
  /// Records watch history *after* the current frame. [WatchHistoryService.record]
  /// calls notifyListeners, which would trip "setState() called during build"
  /// if invoked synchronously from initState (a listening rail on a screen
  /// already built this frame would be marked dirty mid-build). Deferring one
  /// frame side-steps that; the `mounted` guard covers an instantly-closed
  /// player.
  void _scheduleRecordHistory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordHistory();
    });
  }

  void _recordHistory() {
    final ref = _playbackRef;
    if (ref != null) {
      WatchHistoryService.instance.record(WatchHistoryEntry(
        type: ref.type,
        id: ref.id,
        name: ref.type == 'episode'
            ? (widget.seriesName ?? widget.title)
            : widget.title,
        imageUrl: widget.favoriteItem?.imageUrl,
        seriesId: ref.seriesId,
        seasonNumber: ref.seasonNumber,
        episodeNum: ref.episodeNum,
        categoryId: ref.categoryId,
        extra: ref.type == 'movie' ? (widget.favoriteItem?.extra ?? {}) : {},
        watchedAt: DateTime.now(),
      ));
      return;
    }
    final fav = _favoriteItem;
    if (fav != null) {
      WatchHistoryService.instance.record(WatchHistoryEntry(
        type: fav.type,
        id: fav.id,
        name: _title,
        imageUrl: fav.imageUrl,
        categoryId: fav.categoryId,
        watchedAt: DateTime.now(),
      ));
    }
  }

  Future<void> _promptResume(PlaybackProgress saved) async {
    final l = AppLocalizations.of(context)!;
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(l.continueWatchingTitle),
        content: Text(l.resumeBody(_formatDuration(saved.position))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.startOver),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.resume),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      _resumeGuard?.resumeChosen();
      await _player.seek(saved.position);
    } else {
      // Explicitly discarding the mark is the one case where writing a small
      // position back over a large one is what the user asked for.
      _resumeGuard?.startOverChosen();
    }
    _player.play();
  }

  /// After an episode is finished its progress is deleted, which for a series
  /// used to throw away the only record of where the viewer had got to: the
  /// detail screen lost its highlight and its season, and the show dropped out
  /// of continue watching altogether. Point the series at the next episode
  /// instead, so finishing one moves you forward rather than nowhere.
  ///
  /// Position zero and an unknown total on purpose — nothing has been watched
  /// of it yet. progressFraction() reads a zero total as "no bar to draw", so
  /// the entry marks the place without claiming progress that does not exist.
  ///
  /// Crosses season boundaries, unlike autoplay: this is a bookmark, not a
  /// decision to keep playing. Finishing the last episode of the last season
  /// leaves nothing behind, which is correct — the series is done.
  void _advanceSeriesPointer(PlaybackRef ref) {
    if (ref.type != 'episode') return;
    final nav = _navigator;
    if (nav == null) return;
    final at = nav.locate(ref.id);
    if (at == null) return;
    final next = nav.next(at);
    if (next == null) return;
    final episode = nav.episodeAt(next);
    final season = nav.seasonAt(next);
    if (episode == null || season == null) return;

    PlaybackService.instance.save(PlaybackProgress(
      type: 'episode',
      id: episode.id,
      position: Duration.zero,
      total: Duration.zero,
      seriesId: ref.seriesId,
      seasonNumber: season.seasonNumber,
      episodeNum: episode.episodeNum,
      updatedAt: DateTime.now(),
    ));
  }

  void _saveProgress(PlaybackRef ref) {
    final position = _player.state.position;
    final total = _player.state.duration;
    // Duration isn't known until the stream has actually started loading.
    if (total == Duration.zero) return;
    if (position < _resumeThreshold) return;
    // A stalled or failed stream sits near zero while this timer keeps
    // firing; without this it would write that over a real resume point.
    if (!(_resumeGuard?.allowsSaving(position, hasError: _error != null) ??
        _error == null)) {
      return;
    }

    if (position.inMilliseconds / total.inMilliseconds >= _finishedFraction) {
      // Treat as finished rather than "in progress" so reopening this
      // item doesn't prompt to resume the last few seconds of credits.
      PlaybackService.instance.clear(ref.type, ref.id);
      _advanceSeriesPointer(ref);
      return;
    }

    PlaybackService.instance.save(PlaybackProgress(
      type: ref.type,
      id: ref.id,
      position: position,
      total: total,
      seriesId: ref.seriesId,
      seasonNumber: ref.seasonNumber,
      episodeNum: ref.episodeNum,
      updatedAt: DateTime.now(),
    ));
  }

  Future<void> _stop() async {
    // Halt and reset to the start rather than Player.stop(), which unloads
    // the media entirely - this way pressing play again doesn't need to
    // reopen the stream. Live streams aren't seekable (see _seekBy) - for
    // them Stop just pauses, since asking mpv to seek a live stream throws
    // the same "not seekable" error the seek buttons used to hit.
    await _player.pause();
    if (_isVod) await _player.seek(Duration.zero);
  }

  /// Queues a skip. Repeated presses are summed and sent as one seek once they
  /// stop, so hunting for a moment costs one Range request instead of one per
  /// tap - see [SeekAccumulator].
  void _seekBy(Duration delta) {
    if (!_isVod) return;
    _seekAccumulator.add(delta);
    // Move the scrubber straight away so the button still feels instant.
    final total = _player.state.duration;
    var preview = _position + _seekAccumulator.pending;
    if (preview < Duration.zero) preview = Duration.zero;
    if (total > Duration.zero && preview > total) preview = total;
    setState(() => _position = preview);
  }

  Future<void> _applySeekDelta(Duration delta) async {
    // Live channels aren't genuinely seekable - there's no fixed duration
    // to seek within, and asking mpv to seek past the live edge throws
    // "not seekable" ("--force-seekable=yes") instead of clamping quietly.
    // Only on-demand content (movies/episodes) supports seeking.
    if (!_isVod) return;
    final total = _player.state.duration;
    var target = _player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    await _player.seek(target);
  }

  void _showFullTitle() {
    final l = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: SelectableText(_title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  void _onSeekDragChanged(double value) {
    // Dragging supersedes any queued skips - committing them afterwards would
    // yank playback away from where the user just put it.
    _seekAccumulator.cancel();
    setState(() => _seekDragValue = value);
  }

  Future<void> _onSeekDragEnd(double value) async {
    setState(() {
      _position = Duration(milliseconds: value.round());
      _seekDragValue = null;
    });
    await _player.seek(Duration(milliseconds: value.round()));
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _muted = value == 0;
    });
    _player.setVolume(value);
  }

  void _toggleMute() {
    if (_muted || _volume == 0) {
      final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 100.0;
      setState(() {
        _volume = restore;
        _muted = false;
      });
      _player.setVolume(restore);
    } else {
      setState(() {
        _volumeBeforeMute = _volume;
        _volume = 0;
        _muted = true;
      });
      _player.setVolume(0);
    }
  }

  void _setPlaybackRate(double rate) {
    setState(() => _playbackRate = rate);
    _player.setRate(rate);
  }

  void _setVideoFit(BoxFit fit) => setState(() => _videoFit = fit);

  void _setAudioTrack(AudioTrack track) {
    _player.setAudioTrack(track);
    setState(() => _currentAudioId = track.id);
  }

  void _setSubtitleTrack(SubtitleTrack track) {
    _player.setSubtitleTrack(track);
    setState(() => _currentSubtitleId = track.id);
  }

  void _setVideoTrack(VideoTrack track) {
    _player.setVideoTrack(track);
    setState(() => _currentVideoId = track.id);
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    if (isDesktopWindow) {
      if (next) {
        // Win32 will not take a maximized window fullscreen properly: the
        // frame and title bar survive and the video ends up letterboxed
        // inside a still-maximized window rather than filling the display.
        // Drop out of maximized first, and remember to put it back.
        _wasMaximizedBeforeFullscreen = await windowManager.isMaximized();
        if (_wasMaximizedBeforeFullscreen) await windowManager.unmaximize();
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        // Restore the maximized state the user had before, rather than
        // dumping them into a small floating window.
        if (_wasMaximizedBeforeFullscreen) {
          await windowManager.maximize();
          _wasMaximizedBeforeFullscreen = false;
        }
      }
    } else {
      // The mobile equivalent: hide the status and navigation bars rather than
      // resize an OS window. "Sticky" so a stray swipe reveals them briefly
      // and then hides them again, instead of dropping out of fullscreen
      // mid-scene.
      await SystemChrome.setEnabledSystemUIMode(
        next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      // Turn the phone sideways with it: held upright, a 16:9 video occupies
      // barely a third of the screen, so "fullscreen" in portrait isn't much
      // of one. Leaving fullscreen hands orientation back to the device.
      await SystemChrome.setPreferredOrientations(
        next
            ? fullscreenOrientationsFor(
                width: _player.state.width, height: _player.state.height)
            : DeviceOrientation.values,
      );
    }
    if (mounted) setState(() => _isFullscreen = next);
  }

  /// Undoes whatever [_toggleFullscreen] did, without needing the screen to
  /// still be mounted. Called from dispose, where the desktop branch must stay
  /// behind isDesktopWindow: _isFullscreen can now be set on Android too, and
  /// an unguarded windowManager call there throws MissingPluginException.
  void _restoreFromFullscreen() {
    if (isDesktopWindow) {
      windowManager.setFullScreen(false);
      // Leaving the player straight from fullscreen must also undo the
      // unmaximize that getting there required, or the window comes back
      // smaller than the user left it.
      if (_wasMaximizedBeforeFullscreen) {
        _wasMaximizedBeforeFullscreen = false;
        windowManager.maximize();
      }
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // Leaving the player mid-fullscreen must not strand the rest of the app
      // locked to landscape.
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  // Picture-in-Picture, desktop style: the whole OS window shrinks into a
  // small always-on-top corner player (Flutter Windows has no native PiP
  // surface). Exiting — or leaving the player — restores the old bounds.
  bool _isPip = false;
  Rect? _prePipBounds;

  /// Must match the minimum the app sets at startup (main.dart) — restored
  /// when PiP releases its smaller override.
  static const _normalMinSize = Size(900, 640);
  static const _pipMinSize = Size(320, 180);
  static const _pipSize = Size(480, 270);

  Future<void> _togglePip() async {
    // Desktop-only, like fullscreen: this PiP *is* window manipulation.
    // Android gets real native PiP in its own phase instead.
    if (!isDesktopWindow) return;
    if (_isPip) {
      await _exitPip();
    } else {
      // PiP from fullscreen: drop fullscreen first so bounds mean something.
      if (_isFullscreen) await _toggleFullscreen();
      _prePipBounds = await windowManager.getBounds();
      // Chromeless: no title bar or minimize/maximize/close caption buttons —
      // otherwise it reads as "the app, but smaller" instead of a PiP surface.
      // Dragging the video moves the window instead (see the pan handler).
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
          windowButtonVisibility: false);
      await windowManager.setMinimumSize(_pipMinSize);
      await windowManager.setSize(_pipSize);
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.setAlwaysOnTop(true);
      if (mounted) setState(() => _isPip = true);
    }
  }

  Future<void> _exitPip() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal,
        windowButtonVisibility: true);
    await windowManager.setMinimumSize(_normalMinSize);
    final bounds = _prePipBounds;
    if (bounds != null) await windowManager.setBounds(bounds);
    if (mounted) setState(() => _isPip = false);
  }

  void _showControls() {
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (!_isPlaying) return; // stay visible while paused
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // `?` (shift+/) opens the shortcuts reference — works in fullscreen too,
    // where the app-bar help button isn't shown.
    if (event.character == '?') {
      showShortcutsHelp(context, isVod: _isVod, isSeries: _isSeries);
      _showControls();
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        _player.playOrPause();
      case LogicalKeyboardKey.arrowLeft:
        _seekBy(const Duration(seconds: -10));
      case LogicalKeyboardKey.arrowRight:
        _seekBy(const Duration(seconds: 10));
      case LogicalKeyboardKey.arrowUp:
        _setVolume((_volume + 5).clamp(0, 100));
      case LogicalKeyboardKey.arrowDown:
        _setVolume((_volume - 5).clamp(0, 100));
      case LogicalKeyboardKey.bracketLeft:
        if (_isVod) {
          _setPlaybackRate((_playbackRate - 0.25).clamp(0.5, 2.0).toDouble());
        }
      case LogicalKeyboardKey.bracketRight:
        if (_isVod) {
          _setPlaybackRate((_playbackRate + 0.25).clamp(0.5, 2.0).toDouble());
        }
      case LogicalKeyboardKey.pageUp:
        _zapBy(1); // channel up
      case LogicalKeyboardKey.pageDown:
        _zapBy(-1); // channel down
      case LogicalKeyboardKey.keyN:
        // Shift, so plain N stays free and these cannot be hit by accident
        // mid-episode. PageUp/PageDown are already channel zap.
        if (HardwareKeyboard.instance.isShiftPressed) _goToEpisode(1);
      case LogicalKeyboardKey.keyP:
        if (HardwareKeyboard.instance.isShiftPressed) _goToEpisode(-1);
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
      case LogicalKeyboardKey.escape:
        // Only swallowed when there is a fullscreen to leave. Otherwise it
        // bubbles to PopScope and closes the player, which is what Escape has
        // always done here — taking it over unconditionally would strand
        // people who use it to back out.
        if (!_isFullscreen) return KeyEventResult.ignored;
        _toggleFullscreen();
      default:
        return KeyEventResult.ignored;
    }
    _showControls();
    return KeyEventResult.handled;
  }

  void _handleVideoTap() {
    if (_controlsVisible) {
      _hideControlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _autoplayTimer?.cancel();
    _hideControlsTimer?.cancel();
    _startTimeoutTimer?.cancel();
    // Drop rather than flush: seeking a player that is being torn down is
    // pointless, and the final _saveProgress below wants the real position.
    _seekAccumulator.dispose();
    _focusNode.dispose();
    // In external-playback mode the media_kit player was never created, and
    // there's no in-app position to save.
    if (!_external) {
      final ref = _playbackRef;
      if (ref != null) _saveProgress(ref);
      // Leaving the player always releases the screen, even mid-playback -
      // otherwise backing out during a stream would keep the display on for
      // the rest of the session.
      ScreenAwake.set(false);
      // Don't leave the whole app stuck fullscreen after leaving the player.
      if (_isFullscreen) _restoreFromFullscreen();
      // Nor stuck as a tiny always-on-top PiP window. Desktop-only by
      // construction (_togglePip early-returns elsewhere), but the guard makes
      // that a property of this code rather than of a call three screens away.
      if (_isPip && isDesktopWindow) {
        windowManager.setAlwaysOnTop(false);
        windowManager.setTitleBarStyle(TitleBarStyle.normal,
            windowButtonVisibility: true);
        windowManager.setMinimumSize(_normalMinSize);
        final bounds = _prePipBounds;
        if (bounds != null) windowManager.setBounds(bounds);
      }
      _player.dispose();
    }
    super.dispose();
  }

  /// The screen shown when playback is handed off to an external player: no
  /// video surface, just a note and a "play again" button (and an error state
  /// if the external process couldn't start).
  Widget _buildExternalHandoff(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _externalLaunchFailed ? Icons.error_outline : Icons.open_in_new,
                size: 56,
                color: _externalLaunchFailed
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _externalLaunchFailed
                    ? l.externalPlayerLaunchFailed
                    : l.externalPlayerHandoff,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _externalLaunchFailed = false);
                  _launchExternal();
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(l.externalPlayerPlayAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_external) return _buildExternalHandoff(context);
    return PopScope(
      // Back has to unwind fullscreen/PiP before it leaves the player. In
      // fullscreen there is no app bar and the system bars are hidden, so on
      // Android back is the only way out — without this a single press during
      // a film would drop playback entirely instead of just showing the
      // chrome again. Desktop reaches the same path via Escape.
      canPop: !_isFullscreen && !_isPip,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isFullscreen) {
          _toggleFullscreen();
        } else if (_isPip) {
          _togglePip();
        }
      },
      child: Scaffold(
        // No chrome in fullscreen — nor in PiP, where a title/back/shortcuts
        // bar would swallow most of the tiny window.
        appBar: _isFullscreen || _isPip
            ? null
            : AppBar(
                // A long episode title ellipsizes in the bar with no way to
                // read the rest, and on a phone almost all of them do. Tapping
                // it shows the whole thing; a tooltip covers pointer devices,
                // where there is nothing to tap with.
                title: Tooltip(
                  message: _title,
                  child: InkWell(
                    onTap: () => _showFullTitle(),
                    child: Text(_title),
                  ),
                ),
                actions: [
                  // A shortcuts reference is only useful where there are keys
                  // to press. The key handlers themselves stay wired up, so an
                  // attached keyboard still works - this only stops offering a
                  // help sheet full of Space/arrows to someone on a phone.
                  if (isDesktopWindow)
                    IconButton(
                      icon: const Icon(Icons.keyboard_outlined),
                      tooltip:
                          AppLocalizations.of(context)!.keyboardShortcutsTitle,
                      onPressed: () =>
                          showShortcutsHelp(context, isVod: _isVod, isSeries: _isSeries),
                    ),
                  if (_favoriteItem != null)
                    AnimatedBuilder(
                      animation: FavoritesService.instance,
                      builder: (context, _) {
                        final fav = _favoriteItem!;
                        final isFav = FavoritesService.instance
                            .isFavorite(fav.type, fav.id);
                        return IconButton(
                          icon: Icon(isFav ? Icons.star : Icons.star_border,
                              color: isFav ? Colors.amber : null),
                          onPressed: () =>
                              FavoritesService.instance.toggle(fav),
                        );
                      },
                    ),
                ],
              ),
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            children: [
              Expanded(
                child: MouseRegion(
                  onHover: (_) => _showControls(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // media_kit_video's own controls would just duplicate
                      // ours - disable them entirely.
                      Video(
                        controller: _controller,
                        controls: NoVideoControls,
                        fit: _videoFit,
                      ),
                      // Radio: the video surface is black, so show the animated
                      // audio visualizer on top of it. IgnorePointer keeps taps
                      // flowing to the controls-toggle gesture layer below.
                      if (_audioOnly)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AudioOnlyVisualizer(title: _title),
                          ),
                        ),
                      // Sits below the overlay in the stack, so taps land here
                      // (toggling visibility) unless they hit a control above.
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _handleVideoTap,
                          // The PiP window has no title bar to grab — dragging
                          // the video itself moves it. (No-op outside PiP.)
                          onPanStart: _isPip
                              ? (_) => windowManager.startDragging()
                              : null,
                        ),
                      ),
                      // After the tap layer so it sits above it, and outside
                      // the auto-hiding control bar: a countdown you cannot
                      // see is a countdown you cannot cancel.
                      if (_autoplaySecondsLeft > 0 && !_isPip)
                        Positioned(
                          right: 24,
                          bottom: 96,
                          child: _AutoplayCountdown(
                            secondsLeft: _autoplaySecondsLeft,
                            onCancel: _cancelAutoplay,
                            onPlayNow: () {
                              final next = _navigator!.nextInSeason(_cursor!);
                              _cancelAutoplay();
                              if (next != null) _playEpisodeAt(next);
                            },
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            // The EPG "now/next" strip rides with the controls
                            // so it (and any "no guide data" note) fades away
                            // with them instead of sitting on the video the
                            // whole time you're watching.
                            // PiP swaps the full control bar (which would cover
                            // the whole mini window, leaving nothing to drag)
                            // for a one-row micro bar.
                            child: _isPip
                                ? ExcludeFocus(
                                    child: _PipControls(
                                      isPlaying: _isPlaying,
                                      onPlayPause: () => _player.playOrPause(),
                                      onExitPip: _togglePip,
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_epgFuture != null)
                                        _EpgStrip(epgFuture: _epgFuture!),
                                      // Keeps keyboard focus (and shortcuts) on the
                                      // screen-level Focus above rather than letting
                                      // the sliders/buttons steal it via Tab or click.
                                      ExcludeFocus(
                                        child: _ControlsOverlay(
                                          isPlaying: _isPlaying,
                                          isFullscreen: _isFullscreen,
                                          volume: _volume,
                                          muted: _muted,
                                          position: _position,
                                          duration: _duration,
                                          seekDragValue: _seekDragValue,
                                          showSeekControls: _isVod,
                                          showSpeedControl: _isVod,
                                          showChannelControls:
                                              _canZap && !_isVod,
                                          onPrevChannel: () => _zapBy(-1),
                                          showEpisodeControls: _isSeries,
                                          canPrevEpisode: _hasPreviousEpisode,
                                          canNextEpisode: _hasNextEpisode,
                                          onPrevEpisode: () => _goToEpisode(-1),
                                          onNextEpisode: () => _goToEpisode(1),
                                          onNextChannel: () => _zapBy(1),
                                          audioTracks: _audioTracks,
                                          subtitleTracks: _subtitleTracks,
                                          videoTracks: _videoTracks,
                                          currentAudioId: _currentAudioId,
                                          currentSubtitleId: _currentSubtitleId,
                                          currentVideoId: _currentVideoId,
                                          onAudioTrack: _setAudioTrack,
                                          onSubtitleTrack: _setSubtitleTrack,
                                          onVideoTrack: _setVideoTrack,
                                          videoFit: _videoFit,
                                          onVideoFitChanged: _setVideoFit,
                                          playbackRate: _playbackRate,
                                          onPlaybackRateChanged:
                                              _setPlaybackRate,
                                          onPlayPause: () =>
                                              _player.playOrPause(),
                                          onStop: _stop,
                                          onSeekBack30: () => _seekBy(
                                              const Duration(seconds: -30)),
                                          onSeekBack10: () => _seekBy(
                                              const Duration(seconds: -10)),
                                          onSeekForward10: () => _seekBy(
                                              const Duration(seconds: 10)),
                                          onSeekForward30: () => _seekBy(
                                              const Duration(seconds: 30)),
                                          onToggleFullscreen: _toggleFullscreen,
                                          isPip: _isPip,
                                          onTogglePip: _togglePip,
                                          onToggleMute: _toggleMute,
                                          onVolumeChanged: _setVolume,
                                          onSeekDragChanged: _onSeekDragChanged,
                                          onSeekDragEnd: _onSeekDragEnd,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      // Connecting/buffering spinner - transparent to taps so
                      // the video still toggles controls underneath.
                      if (_buffering && _error == null)
                        const Positioned.fill(
                          child: IgnorePointer(child: _BufferingOverlay()),
                        ),
                      // Covers the (black) video with a clear reason + Retry when
                      // the stream can't start or fails, instead of a dead frame.
                      if (_error != null)
                        Positioned.fill(
                          child: _PlaybackErrorOverlay(
                            message: _error!,
                            onRetry: _retry,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tiny control row shown in PiP instead of the full [_ControlsOverlay]:
/// play/pause + exit-PiP, small icons, one line — everything else the mini
/// window offers is "drag to move" and "tap to toggle this bar".
class _PipControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onExitPip;

  const _PipControls({
    required this.isPlaying,
    required this.onPlayPause,
    required this.onExitPip,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white),
            tooltip: l.shortcutPlayPause,
            onPressed: onPlayPause,
          ),
          IconButton(
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
            tooltip: l.pipExit,
            onPressed: onExitPip,
          ),
        ],
      ),
    );
  }
}

/// Semi-transparent control bar overlaid on the bottom of the video -
/// faded out by the parent (via [AnimatedOpacity]) rather than handling
/// its own visibility, so it stays a simple, stateless layout.
class _ControlsOverlay extends StatelessWidget {
  final bool isPlaying;
  final bool isFullscreen;
  final double volume;
  final bool muted;
  final Duration position;
  final Duration duration;
  final double? seekDragValue;
  final bool showSeekControls;
  final bool showSpeedControl;
  final bool showChannelControls;
  final VoidCallback onPrevChannel;
  final VoidCallback onNextChannel;

  /// Episode skip controls, shown for series playback. Mutually exclusive
  /// with the channel controls, which are live-only.
  final bool showEpisodeControls;

  /// Whether there is anywhere to go. Both false at the two ends of a series
  /// — the buttons stay visible but disabled, so the boundary is legible
  /// rather than the control silently vanishing.
  final bool canPrevEpisode;
  final bool canNextEpisode;
  final VoidCallback onPrevEpisode;
  final VoidCallback onNextEpisode;
  final List<AudioTrack> audioTracks;
  final List<SubtitleTrack> subtitleTracks;
  final List<VideoTrack> videoTracks;
  final String? currentAudioId;
  final String? currentSubtitleId;
  final String? currentVideoId;
  final ValueChanged<AudioTrack> onAudioTrack;
  final ValueChanged<SubtitleTrack> onSubtitleTrack;
  final ValueChanged<VideoTrack> onVideoTrack;
  final BoxFit videoFit;
  final ValueChanged<BoxFit> onVideoFitChanged;
  final double playbackRate;
  final ValueChanged<double> onPlaybackRateChanged;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onSeekBack30;
  final VoidCallback onSeekBack10;
  final VoidCallback onSeekForward10;
  final VoidCallback onSeekForward30;
  final VoidCallback onToggleFullscreen;
  final bool isPip;
  final VoidCallback onTogglePip;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSeekDragChanged;
  final ValueChanged<double> onSeekDragEnd;

  const _ControlsOverlay({
    required this.isPlaying,
    required this.isFullscreen,
    required this.volume,
    required this.muted,
    required this.position,
    required this.duration,
    required this.seekDragValue,
    required this.showSeekControls,
    required this.showSpeedControl,
    required this.showChannelControls,
    required this.onPrevChannel,
    required this.showEpisodeControls,
    required this.canPrevEpisode,
    required this.canNextEpisode,
    required this.onPrevEpisode,
    required this.onNextEpisode,
    required this.onNextChannel,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.videoTracks,
    required this.currentAudioId,
    required this.currentSubtitleId,
    required this.currentVideoId,
    required this.onAudioTrack,
    required this.onSubtitleTrack,
    required this.onVideoTrack,
    required this.videoFit,
    required this.onVideoFitChanged,
    required this.playbackRate,
    required this.onPlaybackRateChanged,
    required this.onPlayPause,
    required this.onStop,
    required this.onSeekBack30,
    required this.onSeekBack10,
    required this.onSeekForward10,
    required this.onSeekForward30,
    required this.onToggleFullscreen,
    required this.isPip,
    required this.onTogglePip,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onSeekDragChanged,
    required this.onSeekDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    const iconColor = Colors.white;
    // media_kit always lists the "auto"/"no" pseudo-tracks; the real ones are
    // what decides whether a picker is worth showing. Audio needs a genuine
    // choice (>1); subtitles show whenever any exist (to toggle on/off).
    final realAudio =
        audioTracks.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final realSubtitles =
        subtitleTracks.where((t) => t.id != 'auto' && t.id != 'no').toList();
    // Alternate video renditions (HLS quality variants). Only worth a picker
    // when there's a genuine choice — many streams expose a single video track.
    final realVideo =
        videoTracks.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final showAudioMenu = realAudio.length > 1;
    final showSubtitleMenu = realSubtitles.isNotEmpty;
    final showVideoMenu = realVideo.length > 1;
    // "Auto" (adaptive) is active unless a specific rendition was pinned.
    final videoIsAuto = currentVideoId == null ||
        currentVideoId == 'auto' ||
        realVideo.every((t) => t.id != currentVideoId);
    final subtitleActive = currentSubtitleId != null &&
        currentSubtitleId != 'no' &&
        currentSubtitleId != 'auto';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSeekControls)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(color: iconColor, fontSize: 12),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: iconColor,
                        thumbColor: iconColor,
                        inactiveTrackColor: iconColor.withValues(alpha: 0.3),
                        trackHeight: 2,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: (seekDragValue ??
                                position.inMilliseconds.toDouble())
                            .clamp(
                                0,
                                duration.inMilliseconds > 0
                                    ? duration.inMilliseconds.toDouble()
                                    : 1),
                        min: 0,
                        max: duration.inMilliseconds > 0
                            ? duration.inMilliseconds.toDouble()
                            : 1,
                        onChanged: duration.inMilliseconds > 0
                            ? onSeekDragChanged
                            : null,
                        onChangeEnd: onSeekDragEnd,
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: iconColor, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: Colors.redAccent, size: 10),
                  const SizedBox(width: 6),
                  Text(l.liveBadge,
                      style: const TextStyle(
                          color: iconColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          // Wrap, not Row: how many controls appear varies a lot (VOD adds the
          // seek buttons, live adds channel skip, plus whichever track menus
          // the stream offers and the fullscreen toggle), and on a phone that
          // set overflowed the screen - the row reported "RIGHT OVERFLOWED BY
          // 27 PIXELS" and pushed fullscreen off the edge. Wrapping onto a
          // second line copes with any combination instead of just the one
          // that was measured. A desktop window is wide enough that it stays a
          // single row.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.stop, color: iconColor),
                tooltip: l.stop,
                onPressed: onStop,
              ),
              if (showSeekControls) ...[
                IconButton(
                  icon: const Icon(Icons.replay_30, color: iconColor),
                  tooltip: l.back30,
                  onPressed: onSeekBack30,
                ),
                IconButton(
                  icon: const Icon(Icons.replay_10, color: iconColor),
                  tooltip: l.back10,
                  onPressed: onSeekBack10,
                ),
              ],
              if (showChannelControls)
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: iconColor),
                  tooltip: l.prevChannel,
                  onPressed: onPrevChannel,
                ),
              if (showEpisodeControls)
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: iconColor),
                  tooltip: l.previousEpisode,
                  onPressed: canPrevEpisode ? onPrevEpisode : null,
                ),
              IconButton(
                iconSize: 40,
                icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: iconColor),
                onPressed: onPlayPause,
              ),
              if (showChannelControls)
                IconButton(
                  icon: const Icon(Icons.skip_next, color: iconColor),
                  tooltip: l.nextChannel,
                  onPressed: onNextChannel,
                ),
              if (showEpisodeControls)
                IconButton(
                  icon: const Icon(Icons.skip_next, color: iconColor),
                  tooltip: l.nextEpisode,
                  onPressed: canNextEpisode ? onNextEpisode : null,
                ),
              if (showSeekControls) ...[
                IconButton(
                  icon: const Icon(Icons.forward_10, color: iconColor),
                  tooltip: l.forward10,
                  onPressed: onSeekForward10,
                ),
                IconButton(
                  icon: const Icon(Icons.forward_30, color: iconColor),
                  tooltip: l.forward30,
                  onPressed: onSeekForward30,
                ),
              ],
              if (showSpeedControl)
                PopupMenuButton<double>(
                  tooltip: l.playbackSpeed,
                  initialValue: playbackRate,
                  onSelected: onPlaybackRateChanged,
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 0.5, child: Text('0.5x')),
                    const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                    PopupMenuItem(value: 1.0, child: Text(l.speedNormal)),
                    const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                    const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                    const PopupMenuItem(value: 1.75, child: Text('1.75x')),
                    const PopupMenuItem(value: 2.0, child: Text('2.0x')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '${playbackRate}x',
                      style: const TextStyle(
                        color: iconColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (showVideoMenu)
                PopupMenuButton<VideoTrack>(
                  tooltip: l.videoQuality,
                  icon: const Icon(Icons.high_quality, color: iconColor),
                  onSelected: onVideoTrack,
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: VideoTrack.auto(),
                      checked: videoIsAuto,
                      child: Text(l.qualityAuto),
                    ),
                    for (final t in realVideo)
                      CheckedPopupMenuItem(
                        value: t,
                        checked: !videoIsAuto && t.id == currentVideoId,
                        child: Text(videoTrackLabel(t)),
                      ),
                  ],
                ),
              if (showAudioMenu)
                PopupMenuButton<AudioTrack>(
                  tooltip: l.audioTrack,
                  icon: const Icon(Icons.multitrack_audio, color: iconColor),
                  onSelected: onAudioTrack,
                  itemBuilder: (context) => [
                    for (final t in realAudio)
                      CheckedPopupMenuItem(
                        value: t,
                        checked: t.id == currentAudioId,
                        child: Text(audioTrackLabel(t)),
                      ),
                  ],
                ),
              if (showSubtitleMenu)
                PopupMenuButton<SubtitleTrack>(
                  tooltip: l.subtitles,
                  icon: Icon(
                    subtitleActive
                        ? Icons.closed_caption
                        : Icons.closed_caption_off,
                    color: iconColor,
                  ),
                  onSelected: onSubtitleTrack,
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: SubtitleTrack.no(),
                      checked: !subtitleActive,
                      child: Text(l.off),
                    ),
                    for (final t in realSubtitles)
                      CheckedPopupMenuItem(
                        value: t,
                        checked: t.id == currentSubtitleId,
                        child: Text(subtitleTrackLabel(t)),
                      ),
                  ],
                ),
              PopupMenuButton<BoxFit>(
                tooltip: l.aspectRatio,
                icon: const Icon(Icons.aspect_ratio, color: iconColor),
                onSelected: onVideoFitChanged,
                itemBuilder: (context) => [
                  for (final fit in kVideoFitModes)
                    CheckedPopupMenuItem(
                      value: fit,
                      checked: fit == videoFit,
                      child: Text(_videoFitLabel(fit, l)),
                    ),
                ],
              ),
              // This PiP shrinks the OS window itself, so it stays desktop-only
              // — Android's native PiP is a different mechanism entirely.
              if (isDesktopWindow)
                IconButton(
                  icon: Icon(
                      isPip
                          ? Icons.picture_in_picture_alt
                          : Icons.picture_in_picture_alt_outlined,
                      color: iconColor),
                  tooltip: isPip ? l.pipExit : l.pipEnter,
                  onPressed: onTogglePip,
                ),
              // Fullscreen is offered everywhere: an OS window on desktop, and
              // immersive mode (status/nav bars hidden) on mobile, where a
              // full-bleed video matters more than it does on a big screen.
              IconButton(
                icon: Icon(
                    isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: iconColor),
                tooltip: isFullscreen ? l.exitFullscreen : l.fullscreen,
                onPressed: onToggleFullscreen,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    muted || volume == 0
                        ? Icons.volume_off
                        : volume < 50
                            ? Icons.volume_down
                            : Icons.volume_up,
                    color: iconColor,
                  ),
                  tooltip: muted ? l.unmute : l.mute,
                  onPressed: onToggleMute,
                ),
                // Fixed, narrow width rather than spanning the whole bar -
                // volume is a secondary control and doesn't need the room
                // the seek bar above it does.
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: iconColor,
                      thumbColor: iconColor,
                      inactiveTrackColor: iconColor.withValues(alpha: 0.3),
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: volume,
                      min: 0,
                      max: 100,
                      onChanged: onVolumeChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dim scrim + spinner shown while the stream is opening or rebuffering, so
/// a slow-to-load channel reads as "connecting" rather than a frozen screen.
class _BufferingOverlay extends StatelessWidget {
  const _BufferingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black26,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 14),
            Text(AppLocalizations.of(context)!.connecting,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Full-cover error state with a Retry, shown when a stream can't start or
/// dies mid-playback - a clear message beats an indefinite black screen.
class _PlaybackErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PlaybackErrorOverlay({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context)!.retry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows "Now: X (until 9:00 PM)" and "Next: Y" below the video, for
/// whichever channel is currently playing.
class _EpgStrip extends StatelessWidget {
  final Future<List<EpgProgram>> epgFuture;

  const _EpgStrip({required this.epgFuture});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    String formatTime(DateTime dt) => MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(dt));
    return FutureBuilder<List<EpgProgram>>(
      future: epgFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 32,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final programs = snapshot.data ?? [];
        if (programs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l.noGuideDataChannel,
                style: const TextStyle(fontSize: 12)),
          );
        }

        final now = programs.first;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.nowUntil(now.title, formatTime(now.end)),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(
                      value: now.progress, minHeight: 3),
                ),
              ),
              if (programs.length > 1)
                Text(
                  l.nextProgram(programs[1].title),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The "next episode in Ns" card shown when an episode ends and another is
/// queued behind it.
///
/// Deliberately a card with two explicit buttons rather than a bare timer:
/// autoplay that cannot be stopped is the complaint people actually have
/// about autoplay, and the cancel has to be reachable without hunting.
class _AutoplayCountdown extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onCancel;
  final VoidCallback onPlayNow;

  const _AutoplayCountdown({
    required this.secondsLeft,
    required this.onCancel,
    required this.onPlayNow,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.autoplayCountdown(secondsLeft),
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: onCancel, child: Text(l.cancel)),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onPlayNow,
                  child: Text(l.autoplayPlayNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
