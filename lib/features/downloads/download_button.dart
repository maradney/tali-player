import 'package:flutter/material.dart';

import '../../data/models/download_item.dart';
import '../../data/services/download_service.dart';
import '../../l10n/app_localizations.dart';

/// A self-contained download control for one movie/episode. Reflects live
/// [DownloadService] state and toggles between download / progress+cancel /
/// downloaded / retry. [compact] renders a bare icon (episode rows); otherwise
/// a labelled outlined button (the movie detail action row).
class DownloadButton extends StatelessWidget {
  final DownloadItem item;
  final bool compact;

  const DownloadButton({super.key, required this.item, this.compact = false});

  Future<void> _confirmDelete(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(l.deleteDownloadConfirm),
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
    if (ok == true) await DownloadService.instance.deleteDownload(item.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadService.instance,
      builder: (context, _) {
        final l = AppLocalizations.of(context)!;
        final svc = DownloadService.instance;
        final status = svc.statusFor(item.id);
        final scheme = Theme.of(context).colorScheme;

        switch (status) {
          case null:
            return _action(
                context, Icons.download_outlined, l.download, () => svc.enqueue(item));
          case DownloadStatus.queued:
          case DownloadStatus.downloading:
            return _progress(context, svc.progressFraction(item.id),
                status == DownloadStatus.queued ? l.downloadQueued : l.downloading,
                () => svc.cancel(item.id));
          case DownloadStatus.completed:
            return _action(context, Icons.download_done, l.downloaded,
                () => _confirmDelete(context),
                color: Colors.green);
          case DownloadStatus.failed:
            return _action(
                context, Icons.refresh, l.retryDownload, () => svc.retry(item.id),
                color: scheme.error);
        }
      },
    );
  }

  Widget _action(BuildContext context, IconData icon, String label,
      VoidCallback onTap,
      {Color? color}) {
    if (compact) {
      return IconButton(
        icon: Icon(icon, color: color),
        tooltip: label,
        onPressed: onTap,
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: color == null ? null : TextStyle(color: color)),
    );
  }

  Widget _progress(BuildContext context, double? fraction, String label,
      VoidCallback onCancel) {
    final ring = SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(value: fraction, strokeWidth: 2),
          const Icon(Icons.stop, size: 12),
        ],
      ),
    );
    if (compact) {
      return IconButton(
        icon: ring,
        tooltip: AppLocalizations.of(context)!.cancelDownload,
        onPressed: onCancel,
      );
    }
    final pct = fraction != null ? ' ${(fraction * 100).round()}%' : '';
    return OutlinedButton.icon(
      onPressed: onCancel,
      icon: ring,
      label: Text('$label$pct'),
    );
  }
}
