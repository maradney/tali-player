/// Strips Xtream credentials out of text that quotes a URL, so nothing a human
/// can see or share carries them — the Diagnostics log, and the player's error
/// overlay (mpv reports a failed open with the full URL in the message).
///
/// Credentials show up in two shapes:
///   - **stream URLs put them in the path**, right after the stream kind:
///     `{server}/live/{user}/{pass}/{id}.ts`, and the same for `/movie/`,
///     `/series/` and `/timeshift/` — see `Channel.streamUrl`,
///     `Movie.streamUrl`, `Episode.streamUrl` and
///     `XtreamMediaSource.timeshiftUrl`.
///   - **`player_api.php` puts them in the query**: `?username=U&password=P`.
///
/// The path rule matches on URL *shape*, not on the account's actual
/// credentials, because the caller doesn't always have the account to compare
/// against (a player screen opened from a favorite/history snapshot has only a
/// URL). That means an M3U URL that happens to look like `/movie/a/b/…` gets
/// redacted too. That trade is deliberate: this text is read by people, not
/// parsed, so losing a path segment costs nothing and leaking a password costs
/// a lot.
library;

/// `/live|movie|series|timeshift/<user>/<pass>/` → `/<kind>/***/***/`.
final _pathCredentials = RegExp(
  r'/(live|movie|series|timeshift)/[^/\s]+/[^/\s]+/',
  caseSensitive: false,
);

final _queryUsername = RegExp(r'username=[^&\s]*');
final _queryPassword = RegExp(r'password=[^&\s]*');

/// Returns [message] with any Xtream credentials replaced by `***`.
/// Credential-free text is returned unchanged.
String redactCredentials(String message) => message
    .replaceAll(_queryUsername, 'username=***')
    .replaceAll(_queryPassword, 'password=***')
    .replaceAllMapped(_pathCredentials, (m) => '/${m[1]}/***/***/');
