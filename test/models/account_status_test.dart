import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/models/account_status.dart';

int _epochSecondsFromNow(Duration offset) =>
    DateTime.now().add(offset).millisecondsSinceEpoch ~/ 1000;

void main() {
  group('AccountStatus.fromUserInfoJson', () {
    test('parses a typical active account (string-typed fields)', () {
      final exp = _epochSecondsFromNow(const Duration(days: 10, hours: 1));
      final status = AccountStatus.fromUserInfoJson({
        'status': 'Active',
        'exp_date': '$exp',
        'is_trial': '0',
        'active_cons': '1',
        'max_connections': '2',
        'created_at': '1600000000',
      });
      expect(status.status, 'Active');
      expect(status.isActive, isTrue);
      expect(status.isTrial, isFalse);
      expect(status.activeConnections, 1);
      expect(status.maxConnections, 2);
      expect(status.isUnlimited, isFalse);
      expect(status.isExpired, isFalse);
      expect(status.daysUntilExpiry, inInclusiveRange(9, 10));
      expect(status.atConnectionLimit, isFalse);
      expect(status.createdAt, isNotNull);
    });

    test('coerces numeric (non-string) fields', () {
      final exp = _epochSecondsFromNow(const Duration(days: 5));
      final status = AccountStatus.fromUserInfoJson({
        'status': 'Active',
        'exp_date': exp, // int, not string
        'active_cons': 0,
        'max_connections': 3,
      });
      expect(status.expiresAt, isNotNull);
      expect(status.activeConnections, 0);
      expect(status.maxConnections, 3);
    });

    test('treats missing/empty/zero exp_date as unlimited', () {
      expect(
        AccountStatus.fromUserInfoJson({'status': 'Active'}).isUnlimited,
        isTrue,
      );
      expect(
        AccountStatus.fromUserInfoJson({'exp_date': ''}).isUnlimited,
        isTrue,
      );
      expect(
        AccountStatus.fromUserInfoJson({'exp_date': '0'}).isUnlimited,
        isTrue,
      );
      expect(
        AccountStatus.fromUserInfoJson({'exp_date': ''}).daysUntilExpiry,
        isNull,
      );
    });

    test('detects an expired subscription', () {
      final past = _epochSecondsFromNow(const Duration(days: -2));
      final status =
          AccountStatus.fromUserInfoJson({'status': 'Expired', 'exp_date': '$past'});
      expect(status.isExpired, isTrue);
      expect(status.isActive, isFalse);
      expect(status.daysUntilExpiry, 0); // clamped, never negative
    });

    test('flags a trial account', () {
      expect(
        AccountStatus.fromUserInfoJson({'is_trial': '1'}).isTrial,
        isTrue,
      );
      expect(
        AccountStatus.fromUserInfoJson({'is_trial': '0'}).isTrial,
        isFalse,
      );
    });

    test('atConnectionLimit is true only when all slots are used', () {
      AccountStatus withCons(int active, int max) =>
          AccountStatus.fromUserInfoJson(
              {'active_cons': '$active', 'max_connections': '$max'});
      expect(withCons(1, 2).atConnectionLimit, isFalse);
      expect(withCons(2, 2).atConnectionLimit, isTrue);
      expect(withCons(3, 2).atConnectionLimit, isTrue);
      // Unknown ceiling (0) can't be "at limit".
      expect(withCons(1, 0).atConnectionLimit, isFalse);
    });

    test('handles a completely empty payload without throwing', () {
      final status = AccountStatus.fromUserInfoJson({});
      expect(status.status, isNull);
      expect(status.activeConnections, isNull);
      expect(status.maxConnections, isNull);
      expect(status.isUnlimited, isTrue);
      expect(status.isTrial, isFalse);
    });
  });

  group('summaryLabel', () {
    AccountStatus of({String? status, Duration? expiresIn, bool trial = false}) =>
        AccountStatus.fromUserInfoJson({
          if (status != null) 'status': status,
          if (expiresIn != null)
            'exp_date':
                '${DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000}',
          'is_trial': trial ? '1' : '0',
        });

    test('active with an expiry', () {
      final label =
          of(status: 'Active', expiresIn: const Duration(days: 23, hours: 1))
              .summaryLabel;
      expect(label, anyOf('Active · 23d left', 'Active · 22d left'));
    });

    test('active with no expiry omits the expiry part', () {
      expect(of(status: 'Active').summaryLabel, 'Active');
    });

    test('expired shows just "Expired"', () {
      expect(
        of(status: 'Expired', expiresIn: const Duration(days: -1)).summaryLabel,
        'Expired',
      );
    });

    test('trial is labeled as Trial', () {
      final label =
          of(status: 'Active', trial: true, expiresIn: const Duration(days: 3))
              .summaryLabel;
      expect(label, startsWith('Trial · '));
    });

    test('expiring today reads "expires today"', () {
      expect(
        of(status: 'Active', expiresIn: const Duration(hours: 2)).summaryLabel,
        'Active · expires today',
      );
    });

    test('unknown status falls back to "Unknown"', () {
      expect(of().summaryLabel, 'Unknown');
    });
  });
}
