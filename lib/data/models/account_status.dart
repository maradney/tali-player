/// Subscription/connection status for an account, parsed from the Xtream
/// `user_info` block returned by player_api.php. It's the user's own account
/// info - useful for "when does my subscription expire?" and, especially,
/// the common "why won't anything play?" case (all connection slots in use).
///
/// Every field is optional because panels are inconsistent about which they
/// populate, and values arrive as strings, numbers, or empty/null - parsing
/// coerces defensively rather than trusting types.
class AccountStatus {
  /// e.g. "Active", "Expired", "Banned", "Disabled" - as the panel reports it.
  final String? status;

  /// When the subscription lapses, or null for "no expiry" (unlimited, or
  /// the panel didn't say).
  final DateTime? expiresAt;

  final bool isTrial;

  /// How many streams are open right now, and the account's ceiling.
  final int? activeConnections;
  final int? maxConnections;

  /// When the account was created, if the panel reports it.
  final DateTime? createdAt;

  const AccountStatus({
    this.status,
    this.expiresAt,
    this.isTrial = false,
    this.activeConnections,
    this.maxConnections,
    this.createdAt,
  });

  bool get isUnlimited => expiresAt == null;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whole days until expiry (never negative), or null if unlimited.
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inDays;
  }

  bool get isActive => status?.toLowerCase() == 'active';

  /// A short "status + expiry" label for compact rows, e.g. "Active · 23d
  /// left", "Trial · 3d left", or just "Expired" / "Active" (when there's no
  /// expiry). Connection counts are intentionally left out so the UI can
  /// style them on their own (they turn red at the limit).
  String get summaryLabel {
    final label = isExpired
        ? 'Expired'
        : isTrial
            ? 'Trial'
            : isActive
                ? 'Active'
                : (status ?? 'Unknown');
    if (isUnlimited || isExpired) return label;
    final days = daysUntilExpiry!;
    return '$label · ${days == 0 ? 'expires today' : '${days}d left'}';
  }

  /// True when every connection slot is occupied - the usual reason a stream
  /// refuses to start. Only meaningful when both counts are known and the
  /// ceiling is non-zero.
  bool get atConnectionLimit {
    final active = activeConnections;
    final max = maxConnections;
    return active != null && max != null && max > 0 && active >= max;
  }

  factory AccountStatus.fromUserInfoJson(Map<String, dynamic> json) {
    return AccountStatus(
      status: _nonEmpty(json['status']),
      expiresAt: _unixSeconds(json['exp_date']),
      isTrial: _bool(json['is_trial']),
      activeConnections: _int(json['active_cons']),
      maxConnections: _int(json['max_connections']),
      createdAt: _unixSeconds(json['created_at']),
    );
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  static int? _int(dynamic v) => int.tryParse(v?.toString().trim() ?? '');

  static bool _bool(dynamic v) {
    final s = v?.toString().trim();
    return s == '1' || s == 'true';
  }

  /// Unix epoch seconds (string or number) -> DateTime. Empty, unparseable,
  /// or <= 0 (a common "unlimited" sentinel) becomes null.
  static DateTime? _unixSeconds(dynamic v) {
    final secs = int.tryParse(v?.toString().trim() ?? '');
    if (secs == null || secs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }
}
