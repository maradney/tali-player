/// A user profile — the top layer above playlists (Xtream logins). Each
/// profile owns its own set of playlists and its own isolated local data
/// (favorites, watch history, continue-watching, channel/PIN prefs, and
/// appearance settings), namespaced by [id] throughout the app.
///
/// A profile can optionally be PIN-protected. As with the parental-control
/// lock, the PIN is never stored in plaintext — only a salted SHA-256 hash
/// ([pinHash] + [pinSalt]) is persisted, so someone reading the prefs file on
/// a shared PC can't recover it.
class Profile {
  /// Stable, opaque identity used as the scope prefix for every piece of this
  /// profile's local data. Never derived from the (user-editable) name, so
  /// renaming a profile doesn't orphan its data.
  final String id;

  /// User-facing label, e.g. "Kids" or "Living room".
  final String name;

  final String? pinHash;
  final String? pinSalt;

  /// Whether this is a "kids" profile — one whose visible content is
  /// restricted to an allowlist of categories (see KidsFilterService) and
  /// which is deliberately left PIN-less so a child can enter it freely. The
  /// protection comes from the *other* profiles being PIN-gated, so the child
  /// can only re-enter this one from the startup picker.
  final bool isKids;

  const Profile({
    required this.id,
    required this.name,
    this.pinHash,
    this.pinSalt,
    this.isKids = false,
  });

  /// True when this profile is gated behind a PIN.
  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  Profile copyWith({
    String? name,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    bool? isKids,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        pinHash: clearPin ? null : (pinHash ?? this.pinHash),
        pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
        isKids: isKids ?? this.isKids,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (pinHash != null) 'pinHash': pinHash,
        if (pinSalt != null) 'pinSalt': pinSalt,
        if (isKids) 'isKids': true,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String,
        pinHash: json['pinHash'] as String?,
        pinSalt: json['pinSalt'] as String?,
        isKids: json['isKids'] as bool? ?? false,
      );
}
