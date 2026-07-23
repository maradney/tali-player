import 'package:flutter/material.dart';

import '../../data/models/profile.dart';
import '../../data/services/accounts_service.dart';
import '../../data/services/profiles_service.dart';
import '../../data/services/settings_service.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_screen.dart';
import '../home/home_shell.dart';
import 'kids_setup.dart';
import 'manage_profiles_screen.dart';
import 'profile_switching.dart';

/// Which kind of profile the picker's add flow should create.
enum _ProfileKind { regular, kids }

/// Netflix-style "Who's using this?" gate. Shown at startup when there's more
/// than one profile (or the active one is PIN-protected), and whenever the
/// user picks "Switch profile" from inside the app. Selecting a profile swaps
/// the whole app to that profile's isolated data and enters the shell.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  Future<void> _select(BuildContext context, Profile profile) async {
    if (profile.hasPin) {
      final ok = await promptProfilePin(context, profile);
      if (!ok) return;
    }
    await applyActiveProfile(profile.id);
    if (!context.mounted) return;
    _enterApp(context);
  }

  Future<void> _add(BuildContext context) async {
    // Ask which kind first: a regular profile enters the app to add its first
    // playlist; a kids profile runs its own guided setup (name + PIN nudge +
    // content curation) and stays on the picker afterwards.
    final kind = await _chooseProfileKind(context);
    if (kind == null || !context.mounted) return;
    if (kind == _ProfileKind.kids) {
      await createKidsProfile(context);
      return;
    }
    final name = await _promptName(context);
    if (name == null || !context.mounted) return;
    final profile = await ProfilesService.instance.addProfile(name: name);
    // addProfile already made it active; load its (default) settings too.
    await SettingsService.instance.loadFor(profile.id);
    if (!context.mounted) return;
    // A brand-new profile has no playlists yet — go add the first one.
    _enterApp(context);
  }

  /// Bottom sheet asking whether to create a regular or a kids profile.
  Future<_ProfileKind?> _chooseProfileKind(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return showModalBottomSheet<_ProfileKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: Text(l.addProfile),
              onTap: () => Navigator.pop(context, _ProfileKind.regular),
            ),
            ListTile(
              leading: const Icon(Icons.child_care),
              title: Text(l.addKidsProfile),
              onTap: () => Navigator.pop(context, _ProfileKind.kids),
            ),
          ],
        ),
      ),
    );
  }

  /// Profile management is parent territory: it can edit a kids profile's
  /// allowed content, delete profiles, and change PINs. When a kids profile is
  /// the one signed in, a parent's PIN has to open it — otherwise the child
  /// could simply walk in here and allow themselves everything.
  Future<void> _openManageProfiles(BuildContext context) async {
    if (!await requireParentAccess(context)) return;
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageProfilesScreen()),
    );
  }

  /// Replaces the picker with the app shell for the now-active profile: the
  /// add-playlist flow if it has none yet, otherwise the main HomeShell.
  void _enterApp(BuildContext context) {
    final hasPlaylist = AccountsService.instance.activeAccount != null;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => hasPlaylist ? const HomeShell() : const LoginScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.whoIsUsing),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: l.manageProfiles,
            onPressed: () => _openManageProfiles(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: ProfilesService.instance,
        builder: (context, _) {
          final profiles = ProfilesService.instance.profiles;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Wrap(
                spacing: 28,
                runSpacing: 28,
                alignment: WrapAlignment.center,
                children: [
                  for (final p in profiles)
                    _ProfileTile(
                      profile: p,
                      onTap: () => _select(context, p),
                    ),
                  _AddProfileTile(onTap: () => _add(context)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Prompts for a profile name; returns the trimmed name or null on cancel.
Future<String?> _promptName(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await _showNamePrompt(context, controller, initial);
  } finally {
    controller.dispose();
  }
}

Future<String?> _showNamePrompt(
    BuildContext context, TextEditingController controller, String? initial) {
  final l = AppLocalizations.of(context)!;
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final text = controller.text.trim();
        if (text.isNotEmpty) Navigator.pop(context, text);
      }

      return AlertDialog(
        title: Text(initial == null ? l.addProfile : l.editProfileTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l.profileNameLabel,
            hintText: l.profileNameHint,
          ),
          onSubmitted: (_) => submit(),
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
  );
}

/// Re-exported so the manage screen can share the same name prompt.
Future<String?> promptProfileName(BuildContext context, {String? initial}) =>
    _promptName(context, initial: initial);

const _tileSize = 120.0;

class _ProfileTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;

  const _ProfileTile({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        profile.name.isEmpty ? '?' : profile.name.characters.first.toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: _tileSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Container(
                  width: _tileSize,
                  height: _tileSize,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                  ),
                ),
                if (profile.hasPin)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Icon(Icons.lock, size: 18, color: scheme.onPrimaryContainer),
                  ),
                if (profile.isKids)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Icon(Icons.child_care,
                        size: 18, color: scheme.onPrimaryContainer),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddProfileTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddProfileTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: _tileSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _tileSize,
              height: _tileSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outline, width: 2),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.add, size: 44, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            Text(
              l.addProfile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
