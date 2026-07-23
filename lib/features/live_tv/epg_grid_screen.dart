import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/channel.dart';
import '../../data/models/epg_program.dart';
import '../../data/models/favorite_item.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/cached_poster_image.dart';
import '../common/pin_dialogs.dart';
import '../player/channel_player_screen.dart';
import 'catchup.dart';

const _pxPerMinute = 4.0;
const _rowHeight = 64.0;
const _headerHeight = 32.0;
const _channelColWidth = 160.0;
const _windowDuration = Duration(hours: 6);
const _shiftDuration = Duration(hours: 3);

/// TV-guide style grid: channels down the side, a shared timeline across
/// the top, programs laid out as blocks sized to their duration. Scoped to
/// whichever category the user had open in Live TV, rather than every
/// channel on the account - fetching a day of EPG for hundreds of channels
/// at once isn't something most panels take kindly to.
class EpgGridScreen extends StatefulWidget {
  final Account account;
  final List<Channel> channels;
  final String categoryName;

  const EpgGridScreen({
    super.key,
    required this.account,
    required this.channels,
    required this.categoryName,
  });

  @override
  State<EpgGridScreen> createState() => _EpgGridScreenState();
}

class _EpgGridScreenState extends State<EpgGridScreen> {
  late final _source = MediaSource.forAccount(widget.account);
  final _vLinked = _LinkedScrollControllers();
  final _hLinked = _LinkedScrollControllers();

  final Map<String, List<EpgProgram>> _epg = {};
  bool _loading = true;
  // True when *every* channel's guide fetch failed - almost certainly the
  // server being unreachable, not genuinely-absent EPG. Distinguishes "server
  // down" from the per-row "No guide data" so the whole grid doesn't silently
  // read as "no EPG" during an outage.
  bool _connectionError = false;
  late DateTime _windowStart;

  @override
  void initState() {
    super.initState();
    _windowStart = _alignedNow();
    _loadEpg();
  }

  @override
  void dispose() {
    _vLinked.dispose();
    _hLinked.dispose();
    super.dispose();
  }

  static DateTime _alignedNow() {
    final now = DateTime.now();
    final minute = now.minute - (now.minute % 30);
    return DateTime(now.year, now.month, now.day, now.hour, minute);
  }

  Future<void> _loadEpg() async {
    setState(() {
      _loading = true;
      _connectionError = false;
    });
    // Gentle pacing: this fires one day-long EPG request per channel in the
    // category, and at high concurrency with no pauses that burst reliably
    // trips smaller panels' 429 rate limit - especially stacked on top of
    // browsing and the background catalog sync. Responses are cached on
    // disk (~15 min), so reopening the grid skips most of this anyway.
    const concurrency = 2;
    var failures = 0;
    for (var i = 0; i < widget.channels.length; i += concurrency) {
      final chunk = widget.channels.skip(i).take(concurrency);
      final results = await Future.wait(chunk.map((c) async {
        try {
          final programs = await _source.getSimpleDataTable(c.streamId);
          return MapEntry(c.streamId, programs);
        } catch (_) {
          failures++;
          return MapEntry(c.streamId, <EpgProgram>[]);
        }
      }));
      if (!mounted) return;
      setState(() {
        for (final e in results) {
          _epg[e.key] = e.value;
        }
      });
      if (i + concurrency < widget.channels.length) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
        // Every fetch failing means the server, not the data, is the problem.
        _connectionError =
            widget.channels.isNotEmpty && failures == widget.channels.length;
      });
    }
  }

  void _shiftWindow(Duration delta) {
    setState(() => _windowStart = _windowStart.add(delta));
  }

  void _jumpToNow() {
    setState(() => _windowStart = _alignedNow());
  }

  Future<void> _playChannel(Channel channel) async {
    // Channels here already come from an unlocked category, but re-check
    // both item and category locks for defense in depth (the category could
    // have been locked from elsewhere while this grid was open).
    if (PinLockService.instance
        .isLocked('live', channel.streamId, categoryId: channel.categoryId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToWatch(channel.name));
      if (!ok) return;
    }
    if (!mounted) return;
    final url = _source.liveUrl(channel);
    final index = widget.channels.indexOf(channel);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: channel.name,
          streamUrl: url,
          httpHeaders:
              iptvStreamHeaders(channel, isM3u: widget.account.isM3u),
          epgFuture: Future.value(_epg[channel.streamId] ?? []),
          favoriteItem: FavoriteItem(
            type: 'live',
            id: channel.streamId,
            name: channel.name,
            imageUrl: channel.logoUrl,
            categoryId: channel.categoryId,
          ),
          // Zap through the same category list the grid is showing.
          channels: widget.channels,
          channelIndex: index >= 0 ? index : 0,
          account: widget.account,
        ),
      ),
    );
  }

  /// Opens a past (or in-progress) programme from the panel's archive via its
  /// timeshift URL. Seekable like VOD; no resume tracking, no zapping.
  Future<void> _playCatchup(Channel channel, EpgProgram program) async {
    if (PinLockService.instance
        .isLocked('live', channel.streamId, categoryId: channel.categoryId)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToWatch(channel.name));
      if (!ok) return;
    }
    if (!mounted) return;
    final url = _source.timeshiftUrl(
        channel, program.start, program.end.difference(program.start));
    if (url == null) return; // source without timeshift (never offered for M3U)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: program.title.isEmpty
              ? channel.name
              : '${channel.name} · ${program.title}',
          streamUrl: url,
          seekable: true,
        ),
      ),
    );
  }

  void _showProgramInfo(Channel channel, EpgProgram program) {
    final l = AppLocalizations.of(context)!;
    final canCatchup =
        _source.supportsCatchup(channel) && catchupAvailable(channel, program);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(program.title.isEmpty ? channel.name : program.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_fmtTime(program.start)} - ${_fmtTime(program.end)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (program.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(program.description),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
          if (canCatchup)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(context);
                _playCatchup(channel, program);
              },
              child: Text(l.watchFromStart),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _playChannel(channel);
            },
            child: Text(l.watchChannel),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final windowEnd = _windowStart.add(_windowDuration);
    final totalWidth = _windowDuration.inMinutes * _pxPerMinute;
    final now = DateTime.now();
    final showNowLine = now.isAfter(_windowStart) && now.isBefore(windowEnd);
    final nowLineX =
        now.difference(_windowStart).inSeconds / 60.0 * _pxPerMinute;

    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.guideTitle(widget.categoryName)),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: l.earlier,
            onPressed: () => _shiftWindow(-_shiftDuration),
          ),
          TextButton(onPressed: _jumpToNow, child: Text(l.now)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: l.later,
            onPressed: () => _shiftWindow(_shiftDuration),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_connectionError && !_loading)
            _ConnectivityBanner(onRetry: _loadEpg),
          Expanded(
            child: widget.channels.isEmpty
                ? Center(child: Text(l.noChannelsInCategory))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _channelColWidth,
                        child: Column(
                          children: [
                            const SizedBox(height: _headerHeight),
                            const Divider(height: 1),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _vLinked.a,
                                child: Column(
                                  children: [
                                    for (final c in widget.channels)
                                      _ChannelCell(
                                        channel: c,
                                        onTap: () => _playChannel(c),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            SizedBox(
                              height: _headerHeight,
                              child: SingleChildScrollView(
                                controller: _hLinked.a,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: totalWidth,
                                  height: _headerHeight,
                                  child: Stack(
                                    children: [
                                      for (var m = 0;
                                          m <= _windowDuration.inMinutes;
                                          m += 30)
                                        Positioned(
                                          left: m * _pxPerMinute,
                                          top: 0,
                                          child: Text(
                                            _fmtTime(_windowStart
                                                .add(Duration(minutes: m))),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _vLinked.b,
                                child: SingleChildScrollView(
                                  controller: _hLinked.b,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: totalWidth,
                                    child: Stack(
                                      children: [
                                        Column(
                                          children: [
                                            for (final c in widget.channels)
                                              _ChannelTimelineRow(
                                                channel: c,
                                                programs: _epg[c.streamId] ??
                                                    const [],
                                                windowStart: _windowStart,
                                                windowEnd: windowEnd,
                                                onTapProgram: (p) =>
                                                    _showProgramInfo(c, p),
                                              ),
                                          ],
                                        ),
                                        if (showNowLine)
                                          Positioned(
                                            left: nowLineX,
                                            top: 0,
                                            bottom: 0,
                                            child: Container(
                                              width: 2,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
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

/// Shown across the top of the grid when every channel's guide fetch failed,
/// so an outage reads as "couldn't reach the server" rather than each row
/// quietly claiming "No guide data".
class _ConnectivityBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _ConnectivityBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.guideUnavailable,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(
                onPressed: onRetry,
                child: Text(AppLocalizations.of(context)!.retry)),
          ],
        ),
      ),
    );
  }
}

class _ChannelCell extends StatelessWidget {
  final Channel channel;
  final VoidCallback onTap;

  const _ChannelCell({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: channel.logoUrl != null
                    ? CachedPosterImage(
                        imageUrl: channel.logoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.tv, size: 24),
                      )
                    : const Icon(Icons.tv, size: 24),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.name,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTimelineRow extends StatelessWidget {
  final Channel channel;
  final List<EpgProgram> programs;
  final DateTime windowStart;
  final DateTime windowEnd;
  final void Function(EpgProgram) onTapProgram;

  const _ChannelTimelineRow({
    required this.channel,
    required this.programs,
    required this.windowStart,
    required this.windowEnd,
    required this.onTapProgram,
  });

  @override
  Widget build(BuildContext context) {
    final visible = programs
        .where((p) => p.end.isAfter(windowStart) && p.start.isBefore(windowEnd))
        .toList();

    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: visible.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                AppLocalizations.of(context)!.noGuideData,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          : Stack(
              children: [
                for (final p in visible)
                  _programBlock(context, p),
              ],
            ),
    );
  }

  Widget _programBlock(BuildContext context, EpgProgram p) {
    final startMin = p.start.difference(windowStart).inSeconds / 60.0;
    final endMin = p.end.difference(windowStart).inSeconds / 60.0;
    final windowMinutes = windowEnd.difference(windowStart).inMinutes;
    final left = startMin.clamp(0, windowMinutes) * _pxPerMinute;
    final right = endMin.clamp(0, windowMinutes) * _pxPerMinute;
    final width = (right - left).clamp(24.0, double.infinity);
    final isLive = p.start.isBefore(DateTime.now()) && p.end.isAfter(DateTime.now());

    return Positioned(
      left: left,
      width: width,
      top: 2,
      bottom: 2,
      child: GestureDetector(
        onTap: () => onTapProgram(p),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isLive
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            p.title.isEmpty ? AppLocalizations.of(context)!.untitled : p.title,
            style: const TextStyle(fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Keeps two ScrollControllers' offsets mirrored so a fixed channel column
/// scrolls with the timeline body (vertical), and the timeline header
/// scrolls with the timeline body (horizontal), without either side being
/// the single "owner" - dragging either one moves both.
class _LinkedScrollControllers {
  final ScrollController a = ScrollController();
  final ScrollController b = ScrollController();
  bool _guard = false;

  _LinkedScrollControllers() {
    a.addListener(() => _mirror(a, b));
    b.addListener(() => _mirror(b, a));
  }

  void _mirror(ScrollController from, ScrollController to) {
    if (_guard || !to.hasClients || !from.hasClients) return;
    _guard = true;
    to.jumpTo(from.offset.clamp(
      to.position.minScrollExtent,
      to.position.maxScrollExtent,
    ));
    _guard = false;
  }

  void dispose() {
    a.dispose();
    b.dispose();
  }
}
