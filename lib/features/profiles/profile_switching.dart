import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db/catalog_database.dart';
import '../../data/models/profile.dart';
import '../../data/services/accounts_service.dart';
import '../../data/services/channel_preferences_service.dart';
import '../../data/services/home_strips_service.dart';
import '../../data/services/download_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/profiles_service.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../l10n/app_localizations.dart';

const _minPinLength = 4;

/// Makes [profileId] the active profile: loads its (isolated) appearance
/// settings first so the app re-themes in the same frame it swaps data, then
/// switches ProfilesService — which AccountsService listens to, so the shell
/// reloads the new profile's playlists/favorites/history in place.
Future<void> applyActiveProfile(String profileId) async {
  await SettingsService.instance.loadFor(profileId);
  await ProfilesService.instance.switchTo(profileId);
}

/// Prompts for [profile]'s PIN, returning true only once the correct one is
/// entered (false on cancel). Wrong entries show an inline error and clear the
/// field rather than closing. Mirrors the parental-lock [requirePin] but
/// verifies against ProfilesService for this specific profile.
Future<bool> promptProfilePin(BuildContext context, Profile profile) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  String? error;

  try {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            if (ProfilesService.instance
                .verifyPin(profile.id, controller.text)) {
              Navigator.pop(context, true);
            } else {
              setState(() {
                error = l.pinIncorrect;
                controller.clear();
              });
            }
          }

          return AlertDialog(
            title: Text(l.profilePinEntry(profile.name)),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  InputDecoration(labelText: l.pinLabel, errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l.unlock)),
            ],
          );
        },
      ),
    );
    return result == true;
  } finally {
    controller.dispose();
  }
}

/// The profiles that can vouch for a parent: non-kids profiles with a PIN.
List<Profile> _parentProfilesWithPin() => ProfilesService.instance.profiles
    .where((p) => !p.isKids && p.hasPin)
    .toList();

/// Gates the parent-only surfaces (profile management — and through it a kids
/// profile's allowed-content list, profile deletion, and PIN changes) while a
/// kids profile is the one signed in.
///
/// Returns true when the caller may proceed:
///   - the active profile isn't a kids profile, so a parent is already in; or
///   - no non-kids profile has a PIN, in which case there's nothing to verify
///     against — the child could just pick one of those profiles from the
///     picker instead. That's the gap the kids-setup nudge asks parents to
///     close, and gating here wouldn't add protection, it would only lock a
///     PIN-less parent out of their own settings.
///
/// Otherwise prompts for any parent profile's PIN and returns whether it was
/// entered correctly.
Future<bool> requireParentAccess(BuildContext context) async {
  if (!parentGateRequired()) return true;
  return promptParentPin(context, _parentProfilesWithPin());
}

/// The gate's decision on its own, without the dialog: true when a kids
/// profile is signed in *and* there's a parent PIN to check against. Split out
/// so the rule that actually protects the feature can be tested directly.
@visibleForTesting
bool parentGateRequired() =>
    (ProfilesService.instance.activeProfile?.isKids ?? false) &&
    _parentProfilesWithPin().isNotEmpty;

/// Prompts for the PIN of *any* of [parents] (a child shouldn't have to be
/// told which parent's PIN the app wants). Same shape as [promptProfilePin],
/// which checks one specific profile.
Future<bool> promptParentPin(
    BuildContext context, List<Profile> parents) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  String? error;

  try {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final ok = parents.any((p) =>
                ProfilesService.instance.verifyPin(p.id, controller.text));
            if (ok) {
              Navigator.pop(context, true);
            } else {
              setState(() {
                error = l.pinIncorrect;
                controller.clear();
              });
            }
          }

          return AlertDialog(
            title: Text(l.parentPinTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration:
                  InputDecoration(labelText: l.pinLabel, errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l.unlock)),
            ],
          );
        },
      ),
    );
    return result == true;
  } finally {
    controller.dispose();
  }
}

/// Deletes [profileId] and every trace of it: its playlists, each playlist's
/// per-account local data (favorites, playback, history, PIN/channel prefs,
/// cached catalog), and the profile's own appearance settings. Other profiles
/// are untouched. Mirrors AccountsScreen's per-playlist teardown, looped.
Future<void> deleteProfileWithData(String profileId) async {
  final removed =
      await AccountsService.instance.removeAccountsForProfile(profileId);
  for (final account in removed) {
    await FavoritesService.instance.deleteFor(account);
    await WatchlistService.instance.deleteFor(account);
    await DownloadService.instance.deleteFor(account);
    await PlaybackService.instance.deleteFor(account);
    await WatchHistoryService.instance.deleteFor(account);
    await PinLockService.instance.deleteFor(account);
    await KidsFilterService.instance.deleteFor(account);
    await ChannelPreferencesService.instance.deleteFor(account);
    await HomeStripsService.instance.deleteFor(account);
    await CatalogDatabase.instance.deleteForAccount(account.key);
  }
  await SettingsService.instance.deleteFor(profileId);
  await ProfilesService.instance.removeProfile(profileId);
}

/// Sets or changes [profile]'s PIN. If it already has one, the current PIN is
/// verified first. No-op if the user cancels.
Future<void> showSetProfilePinDialog(
    BuildContext context, Profile profile) async {
  final l = AppLocalizations.of(context)!;
  if (profile.hasPin) {
    final ok = await promptProfilePin(context, profile);
    if (!ok || !context.mounted) return;
  }

  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  String? error;

  final String? newPin;
  try {
    newPin = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void submit() {
            final pin = pinController.text;
            if (pin.length < _minPinLength) {
              setState(() => error = l.pinTooShort(_minPinLength));
              return;
            }
            if (pin != confirmController.text) {
              setState(() => error = l.pinMismatch);
              return;
            }
            Navigator.pop(context, pin);
          }

          return AlertDialog(
            title: Text(profile.hasPin ? l.changePin : l.settingsSetPin),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l.pinNew),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                      labelText: l.pinConfirm, errorText: error),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l.save)),
            ],
          );
        },
      ),
    );
  } finally {
    pinController.dispose();
    confirmController.dispose();
  }

  if (newPin != null) {
    await ProfilesService.instance.setPin(profile.id, newPin);
  }
}

/// Verifies the current PIN, then removes it from [profile]. No-op on cancel.
Future<void> removeProfilePin(BuildContext context, Profile profile) async {
  final ok = await promptProfilePin(context, profile);
  if (!ok) return;
  await ProfilesService.instance.clearPin(profile.id);
}
