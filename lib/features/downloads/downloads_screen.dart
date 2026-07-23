import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../data/models/download_item.dart';
import '../../data/services/download_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../l10n/app_localizations.dart';
import '../common/cached_poster_image.dart';
import '../common/pin_dialogs.dart';
import '../player/channel_player_screen.dart';

/// Manages saved offline downloads: in-progress transfers (cancel), failed
/// ones (retry/delete), and completed ones (play offline / delete), plus a
/// storage summary. Local-only; playing opens the on-disk file.
class DownloadsScreen extends StatelessWidget {
  final Account account;
  const DownloadsScreen({super.key, required this.account});

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final digits = size >= 100 || unit <= 1 ? 0 : 1;
    return '${size.toStringAsFixed(digits)} ${units[unit]}';
  }

  bool _isLocked(DownloadItem item) {
    final lockType = item.type == 'episode' ? 'series' : 'movie';
    final lockId =
        item.type == 'episode' ? (item.seriesId ?? item.id) : item.id;
    return PinLockService.instance
        .isLocked(lockType, lockId, categoryId: item.categoryId);
  }

  Future<void> _play(BuildContext context, DownloadItem item) async {
    final svc = DownloadService.instance;
    final path = svc.localPathFor(item);
    if (path == null) return;
    if (_isLocked(item)) {
      final ok = await requirePin(context,
          title: AppLocalizations.of(context)!.enterPinToOpen(item.name));
      if (!ok) return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelPlayerScreen(
          title: item.seriesName != null
              ? '${item.seriesName} - ${item.name}'
              : item.name,
          streamUrl: path,
          seriesName: item.seriesName,
          // Poster for the history entry this playback records (and the
          // favorite star), same as playing from the detail screens.
          favoriteItem: item.toFavoriteItem(),
          playbackRef: item.playbackRef,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(l.deleteAllDownloadsConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true) await DownloadService.instance.clearAll();
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _DownloadSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.downloadsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l.downloadSettings,
            onPressed: () => _openSettings(context),
          ),
          AnimatedBuilder(
            animation: DownloadService.instance,
            builder: (context, _) => DownloadService.instance.items.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () => _confirmDeleteAll(context),
                    child: Text(l.deleteAllDownloads),
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [DownloadService.instance, PinLockService.instance]),
        builder: (context, _) {
          // Kids allowlist: drop downloads whose category is no longer allowed
          // (episodes map to their series). No-op when the filter is disabled.
          final visible = DownloadService.instance.items.where((d) =>
              !KidsFilterService.instance.isHiddenForItem(
                  d.type == 'episode' ? 'series' : d.type,
                  d.type == 'episode' ? (d.seriesId ?? d.id) : d.id,
                  categoryId: d.categoryId));
          final items = _sorted(visible.toList());
          if (items.isEmpty) {
            return Center(
              child: Text(l.noDownloads,
                  style: TextStyle(color: Theme.of(context).disabledColor)),
            );
          }
          return ListView(
            children: [
              _StorageHeader(),
              for (final item in items)
                _DownloadRow(
                  item: item,
                  onPlay: () => _play(context, item),
                  isLocked: _isLocked(item),
                ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  /// In-progress (downloading/queued) first, then failed, then completed —
  /// each group newest-queued first.
  List<DownloadItem> _sorted(List<DownloadItem> items) {
    int rank(DownloadStatus s) => switch (s) {
          DownloadStatus.downloading => 0,
          DownloadStatus.queued => 1,
          DownloadStatus.failed => 2,
          DownloadStatus.completed => 3,
        };
    final copy = List<DownloadItem>.from(items); // already newest-first
    copy.sort((a, b) => rank(a.status).compareTo(rank(b.status)));
    return copy;
  }
}

/// The speed-limit presets, in display order. `0` KB/s means unlimited; the
/// rest are whole MB/s so the label is a clean "N MB/s".
const _speedPresetsKbps = <int>[0, 1024, 2048, 5120, 10240];

/// Bottom sheet exposing the two global transfer controls — how many downloads
/// run at once, and the combined speed cap. Both write straight through to
/// [DownloadService] (which persists them and applies them live).
class _DownloadSettingsSheet extends StatelessWidget {
  const _DownloadSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final svc = DownloadService.instance;
    return SafeArea(
      child: AnimatedBuilder(
        animation: svc,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(l.downloadSettings,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(l.maxSimultaneousDownloads,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final n in const [1, 2, 3, 4])
                    ChoiceChip(
                      label: Text('$n'),
                      selected: svc.maxConcurrent == n,
                      onSelected: (_) => svc.setMaxConcurrent(n),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(l.speedLimit,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final kbps in _speedPresetsKbps)
                    ChoiceChip(
                      label: Text(kbps == 0
                          ? l.speedUnlimited
                          : l.speedMbps('${kbps ~/ 1024}')),
                      selected: svc.bandwidthLimitKbps == kbps,
                      onSelected: (_) => svc.setBandwidthLimitKbps(kbps),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FutureBuilder<int>(
      // Re-runs whenever the list changes (the parent AnimatedBuilder rebuilds).
      future: DownloadService.instance.totalBytesOnDisk(),
      builder: (context, snap) {
        final text = l.storageUsed(DownloadsScreen.formatBytes(snap.data ?? 0));
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline)),
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onPlay;
  final bool isLocked;

  const _DownloadRow({
    required this.item,
    required this.onPlay,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final svc = DownloadService.instance;
    final title = item.seriesName != null
        ? '${item.seriesName} · ${item.name}'
        : item.name;
    final completed = item.status == DownloadStatus.completed;

    return ListTile(
      onTap: completed ? onPlay : null,
      leading: SizedBox(
        width: 48,
        height: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              item.posterUrl != null
                  ? CachedPosterImage(
                      imageUrl: item.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.movie_outlined))
                  : const Icon(Icons.movie_outlined),
              if (isLocked)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: const Icon(Icons.lock, color: Colors.white, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(context, l, svc),
      trailing: _trailing(context, l, svc, completed),
    );
  }

  Widget _subtitle(
      BuildContext context, AppLocalizations l, DownloadService svc) {
    switch (item.status) {
      case DownloadStatus.downloading:
        final frac = svc.progressFraction(item.id);
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: frac),
        );
      case DownloadStatus.queued:
        return Text(l.downloadQueued);
      case DownloadStatus.failed:
        return Text(l.downloadFailed,
            style: TextStyle(color: Theme.of(context).colorScheme.error));
      case DownloadStatus.completed:
        return Text(l.playOffline);
    }
  }

  Widget _trailing(BuildContext context, AppLocalizations l,
      DownloadService svc, bool completed) {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return IconButton(
          icon: const Icon(Icons.close),
          tooltip: l.cancelDownload,
          onPressed: () => svc.cancel(item.id),
        );
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l.retryDownload,
              onPressed: () => svc.retry(item.id),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l.delete,
              onPressed: () => svc.deleteDownload(item.id),
            ),
          ],
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l.delete,
          onPressed: () => svc.deleteDownload(item.id),
        );
    }
  }
}
