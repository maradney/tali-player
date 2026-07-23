import 'package:flutter/material.dart';

import '../../data/models/profile.dart';
import '../../data/services/profiles_service.dart';
import '../../l10n/app_localizations.dart';
import 'kids_content_screen.dart';
import 'kids_setup.dart';
import 'profile_picker_screen.dart' show promptProfileName;
import 'profile_switching.dart';

/// Management view for profiles: add, rename, set/change/remove a PIN, and
/// delete (which cascades to the profile's playlists and all its data). Reached
/// from the profile picker's app bar.
class ManageProfilesScreen extends StatelessWidget {
  const ManageProfilesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final name = await promptProfileName(context);
    if (name == null) return;
    await ProfilesService.instance.addProfile(name: name);
  }

  Future<void> _rename(BuildContext context, Profile profile) async {
    final name = await promptProfileName(context, initial: profile.name);
    if (name == null) return;
    await ProfilesService.instance.renameProfile(profile.id, name);
  }

  Future<void> _delete(BuildContext context, Profile profile) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.deleteProfileTitle),
        content: Text(l.deleteProfileBody(profile.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await deleteProfileWithData(profile.id);
  }

  /// Opens the allowed-content curation for a kids [profile]. It must be the
  /// active profile so its playlists/allowlist are in scope — switch into it
  /// first if needed (safe here: this screen runs in the picker context, with
  /// no shell to disrupt).
  Future<void> _editContent(BuildContext context, Profile profile) async {
    final previousId = ProfilesService.instance.activeProfileId;
    if (previousId != profile.id) {
      await applyActiveProfile(profile.id);
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KidsContentScreen()),
    );
    // Restore whatever profile was active before editing, so managing a kids
    // profile's content doesn't silently leave the parent switched into it.
    if (previousId != null && previousId != profile.id) {
      await applyActiveProfile(previousId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.manageProfiles)),
      body: AnimatedBuilder(
        animation: ProfilesService.instance,
        builder: (context, _) {
          final profiles = ProfilesService.instance.profiles;
          return ListView(
            children: [
              for (final p in profiles)
                ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      p.isKids ? Icons.child_care : null,
                    ),
                  ),
                  title: Text(p.name),
                  subtitle: p.isKids
                      ? Text(l.kidsProfileBadge)
                      : (p.hasPin ? Text(l.requireProfilePin) : null),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'content':
                          _editContent(context, p);
                        case 'rename':
                          _rename(context, p);
                        case 'pin':
                          showSetProfilePinDialog(context, p);
                        case 'removePin':
                          removeProfilePin(context, p);
                        case 'delete':
                          _delete(context, p);
                      }
                    },
                    itemBuilder: (context) => [
                      if (p.isKids)
                        PopupMenuItem(
                            value: 'content',
                            child: Text(l.kidsManageContent)),
                      PopupMenuItem(value: 'rename', child: Text(l.rename)),
                      // A kids profile is deliberately PIN-less (the child
                      // enters it freely); protection comes from the *other*
                      // profiles having PINs.
                      if (!p.isKids)
                        PopupMenuItem(
                          value: 'pin',
                          child:
                              Text(p.hasPin ? l.changePin : l.settingsSetPin),
                        ),
                      if (!p.isKids && p.hasPin)
                        PopupMenuItem(
                          value: 'removePin',
                          child: Text(l.settingsRemovePin),
                        ),
                      // Keep at least one profile around.
                      if (profiles.length > 1)
                        PopupMenuItem(value: 'delete', child: Text(l.delete)),
                    ],
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l.addProfile),
                onTap: () => _add(context),
              ),
              ListTile(
                leading: const Icon(Icons.child_care),
                title: Text(l.addKidsProfile),
                onTap: () => createKidsProfile(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
