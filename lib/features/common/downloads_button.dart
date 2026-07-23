import 'package:flutter/material.dart';

import '../../data/models/account.dart';
import '../../l10n/app_localizations.dart';
import '../downloads/downloads_screen.dart';

/// App-bar action that jumps to the Downloads screen, shown across the main
/// content pages next to their other top controls (grid density, sort/filter).
/// A shared shortcut so offline downloads are always one tap away, wherever you
/// are in the app. Takes the active [account] because the Downloads screen (and
/// the underlying per-account [DownloadService]) is scoped to it.
class DownloadsButton extends StatelessWidget {
  final Account account;
  const DownloadsButton({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.download_outlined),
      tooltip: AppLocalizations.of(context)!.downloadsTitle,
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadsScreen(account: account),
        ),
      ),
    );
  }
}
