import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/seek_accumulator.dart';

/// Each skip-button press used to issue its own seek, and on an HTTP-streamed
/// file every seek is a fresh Range request that discards the buffer. Tapping
/// +30 five times meant five requests to reach somewhere one could have.
void main() {
  late List<Duration> seeks;
  SeekAccumulator make() => SeekAccumulator(
        onSeek: seeks.add,
        quietPeriod: const Duration(milliseconds: 100),
      );

  setUp(() => seeks = []);

  test('a burst of presses becomes one seek with the summed delta', () {
    fakeAsync((async) {
      final acc = make();
      for (var i = 0; i < 5; i++) {
        acc.add(const Duration(seconds: 30));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(seeks, isEmpty, reason: 'must not fire mid-burst');

      async.elapse(const Duration(milliseconds: 200));
      expect(seeks, [const Duration(seconds: 150)]);
    });
  });

  test('presses in both directions cancel out', () {
    fakeAsync((async) {
      final acc = make();
      acc.add(const Duration(seconds: 30));
      acc.add(const Duration(seconds: -30));
      async.elapse(const Duration(milliseconds: 200));
      // Net zero: nothing worth a request, and seeking to where you already
      // are would still cost a re-buffer.
      expect(seeks, isEmpty);
    });
  });

  test('separate bursts are separate seeks', () {
    fakeAsync((async) {
      final acc = make();
      acc.add(const Duration(seconds: 10));
      async.elapse(const Duration(milliseconds: 200));
      acc.add(const Duration(seconds: 10));
      async.elapse(const Duration(milliseconds: 200));
      expect(seeks, [const Duration(seconds: 10), const Duration(seconds: 10)]);
    });
  });

  test('pending exposes the total so the scrubber can move immediately', () {
    fakeAsync((async) {
      final acc = make();
      acc.add(const Duration(seconds: 30));
      expect(acc.pending, const Duration(seconds: 30));
      expect(acc.hasPending, isTrue);

      acc.add(const Duration(seconds: 30));
      expect(acc.pending, const Duration(seconds: 60));

      async.elapse(const Duration(milliseconds: 200));
      expect(acc.pending, Duration.zero, reason: 'cleared once committed');
      expect(acc.hasPending, isFalse);
    });
  });

  test('cancel drops the burst without seeking', () {
    fakeAsync((async) {
      // Dragging the scrubber supersedes queued skips - committing them after
      // would yank playback away from where the user just put it.
      final acc = make();
      acc.add(const Duration(seconds: 30));
      acc.cancel();
      async.elapse(const Duration(milliseconds: 200));
      expect(seeks, isEmpty);
      expect(acc.pending, Duration.zero);
    });
  });

  test('flush commits straight away', () {
    fakeAsync((async) {
      final acc = make();
      acc.add(const Duration(seconds: 30));
      acc.flush();
      expect(seeks, [const Duration(seconds: 30)]);

      // And a flush with nothing pending is a no-op rather than a seek to 0.
      acc.flush();
      expect(seeks, hasLength(1));
      async.elapse(const Duration(milliseconds: 200));
      expect(seeks, hasLength(1));
    });
  });

  test('dispose leaves no timer behind', () {
    fakeAsync((async) {
      final acc = make();
      acc.add(const Duration(seconds: 30));
      acc.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(seeks, isEmpty);
    });
  });
}
