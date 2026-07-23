import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Centered spinner with an optional caption. Used for the first load of a
/// browse screen so a slow/unresponsive server reads as "connecting" rather
/// than a bare, silent spinner (that first request can hang on the socket
/// timeout for a while before it errors out).
class LoadingState extends StatelessWidget {
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error banner + retry button, shared by the browse screens (Live TV/
/// Movies/Series) and the detail screens - previously each carried its own
/// private copy, which meant fixes had to be applied several times over.
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          if (onRetry != null)
            ElevatedButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context)!.retry),
            ),
        ],
      ),
    );
  }
}

/// Shown in the item pane when the currently selected category is locked
/// and hasn't been unlocked yet this visit - shared by Live TV/Movies/
/// Series for the same reason as [ErrorState].
class LockedCategoryPlaceholder extends StatelessWidget {
  final VoidCallback onUnlock;

  const LockedCategoryPlaceholder({super.key, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 40, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(AppLocalizations.of(context)!.categoryLocked),
          const SizedBox(height: 12),
          ElevatedButton(
              onPressed: onUnlock,
              child: Text(AppLocalizations.of(context)!.unlock)),
        ],
      ),
    );
  }
}
