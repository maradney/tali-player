import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/models/account.dart';
import '../../data/services/accounts_service.dart';
import '../../data/services/catalog_enrichment_service.dart';
import '../../data/services/catalog_sync_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/profiles_service.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';
import '../home/home_shell.dart';

class LoginScreen extends StatefulWidget {
  /// When set, this screen is being used as an "add another playlist" flow
  /// pushed on top of the app (e.g. from AccountsScreen) rather than the
  /// very first screen at startup. On success it calls [onAdded] instead
  /// of navigating to HomeShell itself.
  final VoidCallback? onAdded;

  const LoginScreen({super.key, this.onAdded});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _m3uUrlController = TextEditingController();
  final _epgUrlController = TextEditingController();

  final _api = XtreamApiService();

  @override
  void dispose() {
    _nameController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _m3uUrlController.dispose();
    _epgUrlController.dispose();
    super.dispose();
  }

  AccountSourceKind _sourceKind = AccountSourceKind.xtream;
  bool _loading = false;
  String? _error;

  String get _profileId =>
      ProfilesService.instance.activeProfileId ?? Account.defaultProfileId;

  /// A short stand-in name for an M3U playlist left unnamed: the URL's host
  /// (e.g. `example.com`), or — for a local file — its file name.
  static String _hostOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isNotEmpty) return host;
    final base = url.replaceAll('\\', '/').split('/').last;
    return base.isNotEmpty ? base : url;
  }

  Account get _account {
    final name = _nameController.text.trim();
    if (_sourceKind == AccountSourceKind.m3u) {
      final url = _m3uUrlController.text.trim();
      final epg = _epgUrlController.text.trim();
      return Account.m3u(
        profileId: _profileId,
        // Fall back to the URL's host (short + identifying) rather than the
        // whole URL, which is too long for the playlist label.
        name: name.isEmpty ? _hostOf(url) : name,
        url: url,
        epgUrl: epg.isEmpty ? null : epg,
      );
    }
    return Account(
      profileId: _profileId,
      name: name.isEmpty ? _serverController.text.trim() : name,
      serverUrl: _serverController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );
  }

  /// Picks a local .m3u/.m3u8 file and puts its path in the URL field — the
  /// M3U fetcher reads bare paths from disk like it reads URLs.
  Future<void> _browsePlaylistFile() async {
    const group = XTypeGroup(label: 'M3U', extensions: ['m3u', 'm3u8']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    setState(() => _m3uUrlController.text = file.path);
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Built outside the try so the catch can localize errors per-account.
    final account = _account;
    try {
      // Just validate credentials here - the actual category/channel
      // fetching happens once we're inside the Live TV screen.
      await MediaSource.forAccount(account).validate();
      await AccountsService.instance.addAccount(account);
      await FavoritesService.instance.loadFor(account);
      // Fire-and-forget: this is what makes search feel instant without a
      // visible indexing step - the catalog syncs quietly in the
      // background while the person browses Live TV/Movies/Series. If enhanced
      // search is on, the per-item cast/director crawl continues after it.
      unawaited(CatalogSyncService.instance.syncIfNeeded(account, _api).then(
        (_) => CatalogEnrichmentService.instance.enrichIfEnabled(account, _api),
      ));
      if (!mounted) return;
      if (widget.onAdded != null) {
        widget.onAdded!();
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            describeApiError(e, account, AppLocalizations.of(context)!));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: widget.onAdded != null ? AppBar() : null,
      body: Center(
        child: ConstrainedBox(
          // Keeps the form a sane width on a wide Windows window instead
          // of stretching text fields edge to edge.
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.live_tv,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  widget.onAdded != null ? l.addPlaylist : l.signIn,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SegmentedButton<AccountSourceKind>(
                  segments: [
                    ButtonSegment(
                      value: AccountSourceKind.xtream,
                      label: Text(l.sourceXtream),
                      icon: const Icon(Icons.dns_outlined),
                    ),
                    ButtonSegment(
                      value: AccountSourceKind.m3u,
                      label: Text(l.sourceM3u),
                      icon: const Icon(Icons.link),
                    ),
                  ],
                  selected: {_sourceKind},
                  onSelectionChanged: _loading
                      ? null
                      : (s) => setState(() {
                            _sourceKind = s.first;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l.nameOptional,
                    hintText: l.nameHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_sourceKind == AccountSourceKind.xtream) ...[
                  TextField(
                    controller: _serverController,
                    decoration: InputDecoration(
                      labelText: l.serverUrl,
                      hintText: 'http://example.com:8080',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: l.username,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: l.password,
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onSubmitted: (_) => _loading ? null : _connect(),
                  ),
                ] else ...[
                  TextField(
                    controller: _m3uUrlController,
                    decoration: InputDecoration(
                      labelText: l.playlistUrlOrFile,
                      hintText: 'http://example.com/playlist.m3u8',
                      border: const OutlineInputBorder(),
                      // A playlist can also be a file on disk — browse fills
                      // the field with its path (the fetcher reads either).
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: l.externalPlayerBrowse,
                        onPressed: _loading ? null : _browsePlaylistFile,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _epgUrlController,
                    decoration: InputDecoration(
                      labelText: l.epgUrlOptional,
                      hintText: 'http://example.com/epg.xml',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _loading ? null : _connect(),
                  ),
                ],
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _loading ? null : _connect,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.onAdded != null ? l.add : l.signIn),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}