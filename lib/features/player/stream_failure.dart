/// Why a stream wouldn't open, inferred from an HTTP probe of its URL. Lets the
/// player show a plain-language reason instead of a raw mpv "Failed to open".
enum StreamFailureKind {
  /// The server refused us (401/403, or an anti-bot challenge like Cloudflare's
  /// "Just a moment…"). Common for public streams meant to be watched in a
  /// browser — unplayable by any media player.
  blocked,

  /// The stream is gone (404/410).
  notFound,

  /// Couldn't reach the server at all (timeout, DNS, connection refused).
  unreachable,

  /// Reached the server and it answered, but not with a recognizable failure —
  /// keep whatever the player itself reported.
  unknown,
}

/// Classifies a failed stream from an HTTP probe: its [statusCode] (null when
/// the request never got a response) and an optional [bodySnippet] (the first
/// bytes of the response, used to spot anti-bot challenge pages). Pure.
StreamFailureKind classifyStreamFailure({
  int? statusCode,
  String? bodySnippet,
}) {
  // Anti-bot challenge pages can arrive as 403, 503, or even 200 with tell-tale
  // HTML, so check the body regardless of status first.
  final body = bodySnippet?.toLowerCase() ?? '';
  if (body.contains('just a moment') ||
      body.contains('cloudflare') ||
      body.contains('attention required') ||
      body.contains('cf-browser-verification') ||
      body.contains('challenge-platform')) {
    return StreamFailureKind.blocked;
  }
  if (statusCode == 401 || statusCode == 403) return StreamFailureKind.blocked;
  if (statusCode == 404 || statusCode == 410) return StreamFailureKind.notFound;
  if (statusCode == null) return StreamFailureKind.unreachable;
  return StreamFailureKind.unknown;
}
