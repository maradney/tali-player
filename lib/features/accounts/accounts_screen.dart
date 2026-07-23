import 'package:flutter/material.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/db/catalog_database.dart';
import '../../data/models/account.dart';
import '../../data/models/account_status.dart';
import '../../data/services/accounts_service.dart';
import '../../data/services/channel_preferences_service.dart';
import '../../data/services/home_strips_service.dart';
import '../../data/services/download_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/kids_filter_service.dart';
import '../../data/services/pin_lock_service.dart';
import '../../data/services/playback_service.dart';
import '../../data/services/watch_history_service.dart';
import '../../data/services/watchlist_service.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_screen.dart';

/// Lists saved playlists, lets the user switch the active one, add a new
/// one, or remove one (along with its cached favorites/search index).
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _remove(BuildContext context, Account account) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.removePlaylistTitle),
        content: Text(l.removePlaylistBody(account.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AccountsService.instance.removeAccount(account.key);
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.playlistsTitle)),
      body: AnimatedBuilder(
        animation: AccountsService.instance,
        builder: (context, _) {
          final accounts = AccountsService.instance.accounts;
          final activeKey = AccountsService.instance.activeAccount?.key;
          return ListView(
            children: [
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.noPlaylistsYet),
                ),
              for (final account in accounts)
                ListTile(
                  isThreeLine: true,
                  leading: Icon(
                    account.key == activeKey
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: account.key == activeKey
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(account.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${account.username}@${account.serverUrl}'),
                      const SizedBox(height: 4),
                      // Keyed by account so its fetched state survives list
                      // rebuilds (e.g. switching the active account) instead
                      // of re-hitting the server every time.
                      _AccountStatusLine(
                        key: ValueKey('status_${account.key}'),
                        account: account,
                      ),
                    ],
                  ),
                  onTap: account.key == activeKey
                      ? null
                      : () => AccountsService.instance.switchTo(account.key),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l.remove,
                    onPressed: () => _remove(context, account),
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(l.addPlaylist),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LoginScreen(
                      onAdded: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact per-playlist subscription/connection status shown under each
/// account row. Each row fetches independently so one slow or unreachable
/// server doesn't hold up the others, and failures degrade to a quiet
/// "Status unavailable" rather than an alarming error.
class _AccountStatusLine extends StatefulWidget {
  final Account account;

  const _AccountStatusLine({super.key, required this.account});

  @override
  State<_AccountStatusLine> createState() => _AccountStatusLineState();
}

class _AccountStatusLineState extends State<_AccountStatusLine> {
  final _api = XtreamApiService();

  bool _loading = true;
  bool _failed = false;
  AccountStatus? _status;

  @override
  void initState() {
    super.initState();
    // M3U playlists have no subscription/connection status to fetch.
    if (widget.account.isM3u) {
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final status = await _api.getAccountStatus(widget.account);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final muted = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.outline,
    );

    if (widget.account.isM3u) {
      return Text(l.m3uPlaylist, style: muted);
    }
    if (_loading) {
      return Text(l.checkingStatus, style: muted);
    }
    if (_failed || _status == null) {
      return Text(l.statusUnavailable, style: muted);
    }

    final status = _status!;
    final scheme = Theme.of(context).colorScheme;
    final dotColor = status.isExpired
        ? scheme.error
        : status.isTrial
            ? Colors.orange
            : status.isActive
                ? Colors.green
                : scheme.outline;
    final hasConns =
        status.activeConnections != null && status.maxConnections != null;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _statusSummary(status, l),
            style: muted,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasConns)
          Text(
            ' · ${status.activeConnections}/${status.maxConnections}',
            style: muted.copyWith(
              color: status.atConnectionLimit ? scheme.error : muted.color,
              fontWeight:
                  status.atConnectionLimit ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
      ],
    );
  }
}

/// Localized "status + expiry" summary for the compact account line — mirrors
/// [AccountStatus.summaryLabel] (kept in English for tests) but pulled through
/// the l10n strings.
String _statusSummary(AccountStatus s, AppLocalizations l) {
  final label = s.isExpired
      ? l.statusExpired
      : s.isTrial
          ? l.statusTrial
          : s.isActive
              ? l.statusActive
              : (s.status ?? l.statusUnknown);
  if (s.isUnlimited || s.isExpired) return label;
  final days = s.daysUntilExpiry!;
  return '$label · ${days == 0 ? l.statusExpiresToday : l.statusDaysLeft(days)}';
}
