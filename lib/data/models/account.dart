/// Where a playlist's data comes from. [xtream] is the original Xtream Codes
/// panel (player_api.php + built stream URLs); [m3u] is a flat .m3u/.m3u8
/// playlist of absolute stream URLs (optionally with an XMLTV EPG feed).
enum AccountSourceKind { xtream, m3u }

/// A saved IPTV playlist, persisted locally via AccountsService. Each playlist
/// belongs to exactly one [Profile] ([profileId]); users can add multiple
/// playlists per profile and switch between them.
///
/// Two source kinds share this model ([sourceKind]): an Xtream login (server +
/// username + password) or an M3U playlist ([m3uUrl] + optional [epgUrl]). The
/// unused fields for each kind are left empty rather than split into subclasses,
/// so the storage/secure-password plumbing in AccountsService stays uniform.
class Account {
  /// Owning profile's [Profile.id]. Part of [key], so the same server+username
  /// added under two different profiles is two isolated playlists with
  /// separate favorites/history/catalog. Defaults to the starter profile for
  /// accounts created before profiles existed (the upgrade migration stamps
  /// the real value onto them) and for test fixtures.
  final String profileId;
  final String name; // user-facing label, e.g. "My Provider"
  final String serverUrl; // Xtream: http://example.com:8080 (no trailing slash)
  final String username; // Xtream only
  final String password; // Xtream only

  /// How this playlist's data is fetched. Xtream by default so every existing
  /// save (and test fixture) keeps working unchanged.
  final AccountSourceKind sourceKind;

  /// M3U playlist URL (only for [AccountSourceKind.m3u]).
  final String? m3uUrl;

  /// Optional XMLTV EPG feed URL for an M3U playlist. When null, the app falls
  /// back to the `url-tvg`/`x-tvg-url` declared in the playlist header (if any).
  final String? epgUrl;

  /// Kept in sync with ProfilesService.defaultProfileId. Duplicated as a bare
  /// literal so this model stays free of a dependency on the service layer.
  static const String defaultProfileId = 'default';

  const Account({
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.profileId = defaultProfileId,
    this.sourceKind = AccountSourceKind.xtream,
    this.m3uUrl,
    this.epgUrl,
  });

  /// Convenience constructor for an M3U playlist — no username/password, and the
  /// Xtream-only [serverUrl] left empty (identity comes from [m3uUrl]).
  const Account.m3u({
    required this.name,
    required String url,
    this.epgUrl,
    this.profileId = defaultProfileId,
  })  : sourceKind = AccountSourceKind.m3u,
        m3uUrl = url,
        serverUrl = '',
        username = '',
        password = '';

  bool get isM3u => sourceKind == AccountSourceKind.m3u;

  /// Base URL for player_api.php calls, with credentials attached. Xtream only.
  String get apiBaseUrl =>
      '$serverUrl/player_api.php?username=$username&password=$password';

  /// Deterministic identity for this playlist — the same source is the same
  /// playlist even if the display name changes. Shared by AccountsService
  /// (which account is active), CatalogRow/Favorites (which local data belongs
  /// to which account), and the secure-storage password key. Prefixing with
  /// [profileId] is what isolates one profile's data from another's. M3U keys
  /// off the playlist URL; Xtream off server+username.
  String get key => isM3u
      ? '$profileId|m3u|${m3uUrl ?? ''}'
      : '$profileId|$serverUrl|$username';

  /// Non-secret fields only — safe for shared_preferences. The password is
  /// kept out of this on purpose and stored separately via AccountsService
  /// using flutter_secure_storage (OS keychain/DPAPI), not as plain JSON.
  Map<String, Object?> toMetaJson() => {
        'profileId': profileId,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        // Omitted for Xtream saves so existing entries are byte-identical.
        if (isM3u) 'sourceKind': sourceKind.name,
        if (m3uUrl != null) 'm3uUrl': m3uUrl,
        if (epgUrl != null) 'epgUrl': epgUrl,
      };

  factory Account.fromMetaJson(Map<String, dynamic> json,
          {required String password}) =>
      Account(
        // Older saves (pre-profiles) carry no profileId — treat them as the
        // default profile's; the migration rewrites them explicitly.
        profileId: json['profileId'] as String? ?? defaultProfileId,
        name: json['name'] as String,
        serverUrl: json['serverUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: password,
        // Absent on every pre-M3U save → defaults to Xtream.
        sourceKind: AccountSourceKind.values.firstWhere(
          (k) => k.name == json['sourceKind'],
          orElse: () => AccountSourceKind.xtream,
        ),
        m3uUrl: json['m3uUrl'] as String?,
        epgUrl: json['epgUrl'] as String?,
      );
}
