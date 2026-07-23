import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account.dart';

void main() {
  const account = Account(
    name: 'My Provider',
    serverUrl: 'http://example.com:8080',
    username: 'alice',
    password: 's3cret',
  );

  group('Account', () {
    test('apiBaseUrl embeds credentials', () {
      expect(
        account.apiBaseUrl,
        'http://example.com:8080/player_api.php?username=alice&password=s3cret',
      );
    });

    test('key is profile + server + username, independent of name/password',
        () {
      const renamed = Account(
        name: 'Different label',
        serverUrl: 'http://example.com:8080',
        username: 'alice',
        password: 'rotated',
      );
      // Unspecified profileId defaults to the starter profile.
      expect(account.key, 'default|http://example.com:8080|alice');
      expect(renamed.key, account.key);
    });

    test('key differs when server or username differs', () {
      const other = Account(
        name: 'My Provider',
        serverUrl: 'http://example.com:8080',
        username: 'bob',
        password: 's3cret',
      );
      expect(other.key, isNot(account.key));
    });

    test('the same login under a different profile is a distinct key', () {
      const kids = Account(
        profileId: 'p_kids',
        name: 'My Provider',
        serverUrl: 'http://example.com:8080',
        username: 'alice',
        password: 's3cret',
      );
      expect(kids.key, 'p_kids|http://example.com:8080|alice');
      expect(kids.key, isNot(account.key));
    });

    test('toMetaJson carries the profile and omits the password', () {
      final meta = account.toMetaJson();
      expect(meta, {
        'profileId': 'default',
        'name': 'My Provider',
        'serverUrl': 'http://example.com:8080',
        'username': 'alice',
      });
      expect(meta.containsKey('password'), isFalse);
    });

    test('fromMetaJson defaults a missing profileId to the starter profile',
        () {
      final restored = Account.fromMetaJson(
        {'name': 'Legacy', 'serverUrl': 'http://h:80', 'username': 'u'},
        password: 'pw',
      );
      expect(restored.profileId, 'default');
    });

    test('fromMetaJson rehydrates with a separately-supplied password', () {
      final restored = Account.fromMetaJson(
        account.toMetaJson().cast<String, dynamic>(),
        password: 'from-keychain',
      );
      expect(restored.name, 'My Provider');
      expect(restored.serverUrl, 'http://example.com:8080');
      expect(restored.username, 'alice');
      expect(restored.password, 'from-keychain');
      expect(restored.key, account.key);
    });

    test('defaults to the Xtream source kind', () {
      expect(account.sourceKind, AccountSourceKind.xtream);
      expect(account.isM3u, isFalse);
    });

    test('an Xtream save omits the new fields for byte-identical metadata', () {
      // No sourceKind/m3uUrl/epgUrl keys, so existing entries don't change.
      expect(account.toMetaJson().keys,
          unorderedEquals(['profileId', 'name', 'serverUrl', 'username']));
    });
  });

  group('Account.m3u', () {
    const m3u = Account.m3u(
      name: 'My M3U',
      url: 'http://host/list.m3u8',
      epgUrl: 'http://host/epg.xml',
    );

    test('is flagged as M3U with no credentials', () {
      expect(m3u.sourceKind, AccountSourceKind.m3u);
      expect(m3u.isM3u, isTrue);
      expect(m3u.username, isEmpty);
      expect(m3u.password, isEmpty);
      expect(m3u.m3uUrl, 'http://host/list.m3u8');
      expect(m3u.epgUrl, 'http://host/epg.xml');
    });

    test('key is derived from the playlist URL, not server/username', () {
      expect(m3u.key, 'default|m3u|http://host/list.m3u8');
    });

    test('round-trips through meta JSON (kind + urls preserved)', () {
      final restored = Account.fromMetaJson(
        m3u.toMetaJson().cast<String, dynamic>(),
        password: '',
      );
      expect(restored.sourceKind, AccountSourceKind.m3u);
      expect(restored.m3uUrl, m3u.m3uUrl);
      expect(restored.epgUrl, m3u.epgUrl);
      expect(restored.key, m3u.key);
    });
  });
}
