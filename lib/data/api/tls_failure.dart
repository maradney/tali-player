import 'dart:io';

/// Why a TLS connection failed, when it did.
enum TlsFailure {
  /// The server answered our TLS handshake with something that isn't TLS -
  /// in practice, plain HTTP. Almost always means https:// was used against a
  /// port that only speaks http://, which is the norm for Xtream panels on
  /// 8080. Actionable: change the scheme.
  serverSpeaksPlainHttp,

  /// TLS was attempted and failed for some other reason - an expired,
  /// self-signed or mismatched certificate. Not something the user can fix by
  /// editing the URL, so it gets a different message.
  handshakeFailed,
}

/// Classifies [error] when it is a TLS handshake failure, else null.
///
/// Worth special-casing because the raw text is impenetrable: dart:io surfaces
/// this as `HandshakeException: Handshake error in client (OS Error:
/// WRONG_VERSION_NUMBER(tls_record.cc:127))`, which tells the user nothing and
/// hides a one-word fix.
///
/// The check walks [DioException.error]-style wrapping by accepting the inner
/// error directly; callers pass whatever they hold.
TlsFailure? classifyTlsFailure(Object? error) {
  if (error is! HandshakeException) return null;
  // OpenSSL's code for "this isn't a TLS record" - i.e. the peer replied in
  // cleartext. Matched on the message because dart:io does not expose the
  // underlying code any other way.
  if (error.toString().contains('WRONG_VERSION_NUMBER')) {
    return TlsFailure.serverSpeaksPlainHttp;
  }
  return TlsFailure.handshakeFailed;
}
