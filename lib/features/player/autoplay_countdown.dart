import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// The "next episode in Ns" card shown when an episode ends and another is
/// queued behind it.
///
/// Deliberately a card with two explicit buttons rather than a bare timer:
/// autoplay that cannot be stopped is the complaint people actually have
/// about autoplay, and the cancel has to be reachable without hunting.
class AutoplayCountdown extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onCancel;
  final VoidCallback onPlayNow;

  const AutoplayCountdown({
    super.key,
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
