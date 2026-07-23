import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/services/diagnostics_log.dart';

void main() {
  final log = DiagnosticsLog.instance;

  setUp(log.clear);

  test('add appends entries oldest-first', () {
    log.add('one');
    log.add('two');
    expect(log.entries.map((e) => e.message), ['one', 'two']);
  });

  test('notifies listeners on add and clear', () {
    var notifications = 0;
    void listener() => notifications++;
    log.addListener(listener);
    log.add('x');
    log.clear();
    log.removeListener(listener);
    expect(notifications, 2);
  });

  test('clear on an empty log does not notify', () {
    var notifications = 0;
    void listener() => notifications++;
    log.addListener(listener);
    log.clear(); // already empty
    log.removeListener(listener);
    expect(notifications, 0);
  });

  test('caps at 200 entries, dropping the oldest', () {
    for (var i = 0; i < 250; i++) {
      log.add('e$i');
    }
    expect(log.entries, hasLength(200));
    expect(log.entries.first.message, 'e50'); // 0..49 dropped
    expect(log.entries.last.message, 'e249');
  });

  test('asText renders one line per entry, oldest-first', () {
    log.add('alpha');
    log.add('beta');
    final lines = log.asText().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, contains('alpha'));
    expect(lines.last, contains('beta'));
  });
}
