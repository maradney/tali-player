import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_info.dart';
import '../../l10n/app_localizations.dart';

/// Bumping this forces the dialog to reappear once for everyone, even
/// people who already dismissed an older version - use it if the wording
/// ever changes in a way that matters (e.g. legal review).
// v2: wording expanded to cover M3U playlists and downloads (pre-release
// P0 re-audit) — everyone sees the updated text once.
const _acknowledgedPrefsKey = 'disclaimer_acknowledged_v2';

/// Shows the disclaimer once, the first time the app is ever opened.
/// Safe to call on every launch - it's a no-op after the first
/// acknowledgment. Call after the first frame so it layers on top of
/// whatever screen (Login or HomeShell) is already showing.
Future<void> maybeShowFirstRunDisclaimer(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_acknowledgedPrefsKey) == true) return;
  if (!context.mounted) return;
  await showDisclaimerDialog(context, dismissible: false);
  await prefs.setBool(_acknowledgedPrefsKey, true);
}

/// Wraps the app's home widget and triggers [maybeShowFirstRunDisclaimer]
/// once the first frame is up - a bare StatelessWidget can't hook
/// initState, so this exists purely to get that lifecycle callback in
/// front of whichever screen (Login or HomeShell) is actually showing.
class DisclaimerGate extends StatefulWidget {
  final Widget child;

  const DisclaimerGate({super.key, required this.child});

  @override
  State<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends State<DisclaimerGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowFirstRunDisclaimer(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows the same disclaimer on demand (e.g. from an "About" button), so
/// it's not something people only see once and can never find again.
Future<void> showDisclaimerDialog(
  BuildContext context, {
  bool dismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: dismissible,
    builder: (context) {
      final l = AppLocalizations.of(context)!;
      return PopScope(
        canPop: dismissible,
        child: AlertDialog(
          title: Text(l.settingsAboutThisApp),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.disclaimerBody),
                const SizedBox(height: 16),
                Text(
                  l.disclaimerFontsNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  showLicensePage(context: context, applicationName: appName),
              child: Text(l.licenses),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(dismissible ? l.close : l.iUnderstand),
            ),
          ],
        ),
      );
    },
  );
}
