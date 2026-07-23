import 'package:flutter/material.dart';

import '../../data/api/xtream_api_service.dart';
import '../../data/models/account.dart';
import '../../data/models/account_status.dart';
import '../../l10n/app_localizations.dart';
import '../common/api_error_helper.dart';

/// Shows the active account's subscription/connection status - fetched live
/// from the panel (this info, especially the connection count, changes moment
/// to moment, so it isn't cached). Surfaces the two things the app otherwise
/// can't answer: when the subscription expires, and whether every connection
/// slot is in use (the usual reason a stream won't start).
class AccountStatusCard extends StatefulWidget {
  final Account account;

  const AccountStatusCard({super.key, required this.account});

  @override
  State<AccountStatusCard> createState() => _AccountStatusCardState();
}

class _AccountStatusCardState extends State<AccountStatusCard> {
  final _api = XtreamApiService();

  bool _loading = true;
  String? _error;
  AccountStatus? _status;

  @override
  void initState() {
    super.initState();
    // M3U playlists have no subscription/connection status to report.
    if (!widget.account.isM3u) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api.getAccountStatus(widget.account);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiError(e, widget.account, AppLocalizations.of(context)!);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // No status concept for M3U — render nothing rather than a doomed card.
    if (widget.account.isM3u) return const SizedBox.shrink();
    final l = AppLocalizations.of(context)!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.account.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: l.refresh,
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(l.checkingAccountStatus),
                  ],
                ),
              )
            else if (_error != null)
              _ErrorRow(message: _error!, onRetry: _load)
            else if (_status != null)
              _StatusBody(status: _status!),
          ],
        ),
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  final AccountStatus status;

  const _StatusBody({required this.status});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusChip(status: status),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.event_outlined,
          label: l.expiry,
          value: _expiryText(context, l),
          emphasize: status.isExpired,
        ),
        if (status.activeConnections != null && status.maxConnections != null) ...[
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.devices_outlined,
            label: l.connections,
            value: l.connectionsInUse(
                status.activeConnections!, status.maxConnections!),
            emphasize: status.atConnectionLimit,
          ),
        ],
        if (status.atConnectionLimit) ...[
          const SizedBox(height: 8),
          Text(
            l.allConnectionsInUse,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  String _expiryText(BuildContext context, AppLocalizations l) {
    if (status.isUnlimited) return l.noExpiry;
    final date =
        MaterialLocalizations.of(context).formatMediumDate(status.expiresAt!);
    if (status.isExpired) return l.expiredOn(date);
    final days = status.daysUntilExpiry!;
    final left = days == 0 ? l.expiryToday : l.expiryInDays(days);
    return l.expiresLeft(left, date);
  }
}

class _StatusChip extends StatelessWidget {
  final AccountStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final (String label, Color color) = switch (status) {
      _ when status.isExpired => (l.statusExpired, scheme.error),
      _ when status.isTrial => (l.statusTrial, Colors.orange),
      _ when status.isActive => (l.statusActive, Colors.green),
      _ when status.status != null => (status.status!, scheme.outline),
      _ => (l.statusUnknown, scheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor =
        emphasize ? Theme.of(context).colorScheme.error : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: valueColor,
                  fontWeight: emphasize ? FontWeight.w600 : null,
                ),
          ),
        ),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRow({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
            onPressed: onRetry,
            child: Text(AppLocalizations.of(context)!.retry)),
      ],
    );
  }
}
