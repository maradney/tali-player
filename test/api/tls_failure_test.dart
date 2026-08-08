import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/api/tls_failure.dart';

/// Recognising a TLS handshake failure so the user gets advice instead of
/// "WRONG_VERSION_NUMBER(tls_record.cc:127)".
///
/// The exceptions here are constructed the way dart:io constructs them, so the
/// matching is tested against the real shape rather than a string invented to
/// suit the implementation.
void main() {
  group('classifyTlsFailure', () {
    test('spots a server answering TLS in cleartext', () {
      // Exactly what a phone reported against an Xtream panel on :8080 when
      // the URL said https://.
      final error = const HandshakeException(
        'Handshake error in client',
        OSError('WRONG_VERSION_NUMBER(tls_record.cc:127)'),
      );
      expect(classifyTlsFailure(error), TlsFailure.serverSpeaksPlainHttp);
    });

    test('treats other handshake failures separately', () {
      // A certificate problem is not fixed by editing the scheme, so it must
      // not produce the "try http://" advice.
      final error = const HandshakeException(
        'Handshake error in client',
        OSError('CERTIFICATE_VERIFY_FAILED: certificate has expired'),
      );
      expect(classifyTlsFailure(error), TlsFailure.handshakeFailed);
    });

    test('a handshake failure with no OS detail is still a handshake failure',
        () {
      expect(classifyTlsFailure(const HandshakeException()),
          TlsFailure.handshakeFailed);
    });

    test('ignores everything that is not a handshake failure', () {
      // These reach the same catch block and must fall through to their own
      // handling rather than being mislabelled as a TLS problem.
      expect(classifyTlsFailure(null), isNull);
      expect(classifyTlsFailure(const SocketException('Connection refused')),
          isNull);
      expect(classifyTlsFailure(const FormatException('bad json')), isNull);
      expect(classifyTlsFailure('WRONG_VERSION_NUMBER'), isNull,
          reason: 'a bare string must not match on text alone');
      expect(classifyTlsFailure(Exception('WRONG_VERSION_NUMBER')), isNull);
    });
  });
}
