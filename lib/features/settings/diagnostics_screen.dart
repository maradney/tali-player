import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/catalog_row.dart';
import '../../data/models/search_result.dart';
import '../../data/services/diagnostics_log.dart';
import '../../data/sources/media_source.dart';
import '../../l10n/app_localizations.dart';

/// Settings > Diagnostics: a support/debugging screen built from local data.
/// System info, an on-demand connectivity test against the active panel, the
/// in-session event log (API retries/failures), and a cache-clear action.
/// Reads only the user's own data and makes exactly one network call — and
/// only when they tap "Run test".
class DiagnosticsScreen extends StatefulWidget {
  final Account account;
  const DiagnosticsScreen({super.key, required this.account});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _api = XtreamApiService();
  late final String _accountKey = CatalogRow.accountKeyFor(widget.account);

  int? _live, _movies, _series;
  DateTime? _lastSync;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final db = CatalogDatabase.instance;
    final live = await db.countFor(_accountKey, type: ContentType.live);
    final movies = await db.countFor(_accountKey, type: ContentType.movie);
    final series = await db.countFor(_accountKey, type: ContentType.series);
    // Most-recent successful sync across the three types.
    DateTime? last;
    for (final t in ContentType.values) {
      final s = await db.typeSyncedAt(_accountKey, t);
      if (s != null && (last == null || s.isAfter(last))) last = s;
    }
    if (!mounted) return;
    setState(() {
      _live = live;
      _movies = movies;
      _series = series;
      _lastSync = last;
    });
  }

  Future<void> _runConnectivityTest() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final sw = Stopwatch()..start();
    try {
      // Xtream pings the panel (getAccountStatus doesn't throw for an expired
      // account); M3U instead checks the playlist URL is reachable + parseable.
      if (widget.account.isM3u) {
        await MediaSource.forAccount(widget.account).validate();
      } else {
        await _api.getAccountStatus(widget.account, maxRetries: 0);
      }
      sw.stop();
      DiagnosticsLog.instance
          .add('Connectivity test OK (${sw.elapsedMilliseconds} ms)');
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = l.diagnosticsReachable(sw.elapsedMilliseconds);
      });
    } catch (e) {
      sw.stop();
      DiagnosticsLog.instance.add('Connectivity test failed');
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = l.diagnosticsFailed(e.toString());
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearImageCache() async {
    final l = AppLocalizations.of(context)!;
    await DefaultCacheManager().emptyCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.imageCacheCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final materialLoc = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.diagnosticsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l.diagnosticsSystemInfo),
          ListTile(
            dense: true,
            title: Text(l.diagnosticsPlatform),
            subtitle:
                Text('${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
          ),
          ListTile(
            dense: true,
            title: Text(l.diagnosticsPlaylist),
            subtitle: Text(widget.account.name),
          ),
          ListTile(
            dense: true,
            title: Text(l.diagnosticsCatalog),
            subtitle: Text(
              (_live == null)
                  ? '…'
                  : l.diagnosticsCatalogSummary(_live!, _movies!, _series!),
            ),
          ),
          ListTile(
            dense: true,
            title: Text(l.diagnosticsLastSync),
            subtitle: Text(_lastSync == null
                ? l.syncNever
                : '${materialLoc.formatShortDate(_lastSync!)} '
                    '${materialLoc.formatTimeOfDay(TimeOfDay.fromDateTime(_lastSync!))}'),
          ),
          const Divider(),
          _SectionHeader(l.diagnosticsConnectivity),
          ListTile(
            title: Text(widget.account.serverUrl),
            subtitle: _testResult == null
                ? null
                : Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testOk ? Colors.green : Theme.of(context).colorScheme.error,
                    ),
                  ),
            trailing: _testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonal(
                    onPressed: _runConnectivityTest,
                    child: Text(l.diagnosticsRunTest),
                  ),
          ),
          const Divider(),
          _LogSection(),
          const Divider(),
          _SectionHeader(l.diagnosticsMaintenance),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(l.settingsClearImageCache),
            subtitle: Text(l.clearImageCacheSubtitle),
            onTap: _clearImageCache,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// The in-session event log, with copy/clear actions. Listens to
/// [DiagnosticsLog] so new API breadcrumbs appear live.
class _LogSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: DiagnosticsLog.instance,
      builder: (context, _) {
        final entries = DiagnosticsLog.instance.entries.reversed.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(child: _SectionHeader(l.diagnosticsSessionLog)),
                  TextButton(
                    onPressed: entries.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(
                                text: DiagnosticsLog.instance.asText()));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(l.diagnosticsLogCopied)));
                            }
                          },
                    child: Text(l.diagnosticsCopyLog),
                  ),
                  TextButton(
                    onPressed: entries.isEmpty
                        ? null
                        : DiagnosticsLog.instance.clear,
                    child: Text(l.diagnosticsClearLog),
                  ),
                ],
              ),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(l.diagnosticsLogEmpty,
                    style: TextStyle(color: Theme.of(context).disabledColor)),
              )
            else
              for (final e in entries)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Text(
                    '${e.time.hour.toString().padLeft(2, '0')}:'
                    '${e.time.minute.toString().padLeft(2, '0')}:'
                    '${e.time.second.toString().padLeft(2, '0')}  ${e.message}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
          ],
        );
      },
    );
  }
}
