import 'package:flutter/material.dart';

import '../../data/services/profiles_service.dart';
import '../../data/services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import 'kids_content_screen.dart';
import 'profile_picker_screen.dart' show promptProfileName;
import 'profile_switching.dart';

/// Full create-a-kids-profile flow, launched from profile management (a
/// parent-only surface): name it, remind the parent to PIN their other
/// profiles (the cage only holds if the kid can't pick another profile at
/// startup), then curate its allowed content. The new profile is made active
/// so its playlists and allowlist are the ones in scope for curation.
Future<void> createKidsProfile(BuildContext context) async {
  final name = await promptProfileName(context);
  if (name == null || !context.mounted) return;

  final profile =
      await ProfilesService.instance.addProfile(name: name, isKids: true);
  // addProfile made it active; load its (default) settings so the app is fully
  // switched into it before we curate.
  await SettingsService.instance.loadFor(profile.id);
  if (!context.mounted) return;

  await showSiblingPinNudge(context);
  if (!context.mounted) return;

  await Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const KidsContentScreen()),
  );
}

/// Reminds the parent to protect their *other* profiles with a PIN — listing
/// exactly the ones that lack one, each with a one-tap "Set PIN". Informational
/// (not enforced): the parent is responsible, we just make it easy and clear.
Future<void> showSiblingPinNudge(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context)!;
      return AnimatedBuilder(
        animation: ProfilesService.instance,
        builder: (context, _) {
          // Every non-kids profile without a PIN is a way around the filter.
          final unprotected = ProfilesService.instance.profiles
              .where((p) => !p.isKids && !p.hasPin)
              .toList();
          return AlertDialog(
            title: Text(l.kidsSiblingPinTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.kidsSiblingPinBody),
                const SizedBox(height: 16),
                if (unprotected.isEmpty)
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l.kidsSiblingPinAllSet)),
                    ],
                  )
                else
                  for (final p in unprotected)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_open),
                      title: Text(p.name),
                      trailing: TextButton(
                        onPressed: () => showSetProfilePinDialog(context, p),
                        child: Text(l.settingsSetPin),
                      ),
                    ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.kidsSiblingPinDone),
              ),
            ],
          );
        },
      );
    },
  );
}
