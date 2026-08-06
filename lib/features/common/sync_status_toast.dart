import 'package:flutter/material.dart';

import '../../data/models/search_result.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../l10n/app_localizations.dart';

/// The syncing content types as a localized, comma-joined label ("Live TV,
/// Movies"), using the same names as the nav destinations.
String syncStageLabel(AppLocalizations l, List<ContentType> stages) => stages
    .map((t) => switch (t) {
          ContentType.live => l.navLiveTv,
          ContentType.movie => l.navMovies,
          ContentType.series => l.navSeries,
        })
    .join(', ');

/// A small, closable progress card showing background catalog indexing.
///
/// Two shapes, because floating works on a desktop window and does not on a
/// phone. [SyncStatusToast] anchors to the bottom-right via a [Stack], where
/// there is plenty of room beside the content. [SyncStatusBanner] is the
/// phone form: full width and taking real layout space, since a floating card
/// on a ~410dp screen sat on top of the bottom row of posters and hid their
/// titles.
///
/// Neither is part of the navigation stack, so pushing a route (like the
/// player) covers it and it never appears there.
class SyncStatusToast extends StatefulWidget {
  const SyncStatusToast({super.key});

  @override
  State<SyncStatusToast> createState() => _SyncStatusToastState();
}

class _SyncStatusToastState extends State<SyncStatusToast> {
  @override
  Widget build(BuildContext context) => _SyncStatusCard(
        builder: (context, card) => Positioned(bottom: 12, right: 12, child: card),
        width: 260,
      );
}

/// The phone form: full-width, occupying layout space rather than hovering.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) =>
      _SyncStatusCard(builder: (context, card) => card);
}

class _SyncStatusCard extends StatefulWidget {
  /// Wraps the finished card for its context (positioned, or as-is).
  final Widget Function(BuildContext context, Widget card) builder;

  /// Fixed width for the floating form; null makes it fill its parent.
  final double? width;

  const _SyncStatusCard({required this.builder, this.width});

  @override
  State<_SyncStatusCard> createState() => _SyncStatusCardState();
}

class _SyncStatusCardState extends State<_SyncStatusCard> {
  bool _dismissed = false;
  bool _wasSyncing = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CatalogSyncService.instance,
      builder: (context, _) {
        final syncing = CatalogSyncService.instance.isSyncing;

        // A fresh sync starting (e.g. the manual refresh button, or a
        // periodic re-sync) should reappear even if the last one was
        // dismissed.
        if (syncing && !_wasSyncing) _dismissed = false;
        _wasSyncing = syncing;

        if (!syncing || _dismissed) return const SizedBox.shrink();

        final progress = CatalogSyncService.instance.progress;
        final stage = syncStageLabel(AppLocalizations.of(context)!,
            CatalogSyncService.instance.activeStages);

        return widget.builder(
          context,
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Container(
              width: widget.width,
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLocalizations.of(context)!.indexingCatalog(stage),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: AppLocalizations.of(context)!.dismiss,
                    onPressed: () => setState(() => _dismissed = true),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
