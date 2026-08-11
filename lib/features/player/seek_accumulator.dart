import 'dart:async';

/// Collapses a burst of skip-button presses into a single seek.
///
/// Each press of -30/-10/+10/+30 used to issue its own `Player.seek`, and on an
/// HTTP-streamed file every seek is a fresh Range request that throws away the
/// buffer built so far. Hunting for a moment - tap +30 five times - therefore
/// meant five requests and five re-buffers to reach a place one request could
/// have reached. Holding the deltas for a moment and sending the total once is
/// both faster and gentler on a provider that rate-limits.
///
/// The pending total is exposed so the UI can move the scrubber immediately;
/// the seek itself lands when the presses stop.
class SeekAccumulator {
  SeekAccumulator({
    required this.onSeek,
    this.quietPeriod = const Duration(milliseconds: 400),
  });

  /// Called once per burst with the summed delta.
  final void Function(Duration total) onSeek;

  /// How long to wait for another press before committing. Long enough to
  /// catch deliberate repeat taps, short enough not to feel unresponsive.
  final Duration quietPeriod;

  Duration _pending = Duration.zero;
  Timer? _timer;

  /// What has been requested but not yet sent - add this to the current
  /// position to show the user where they are heading.
  Duration get pending => _pending;

  bool get hasPending => _timer?.isActive ?? false;

  void add(Duration delta) {
    _pending += delta;
    _timer?.cancel();
    _timer = Timer(quietPeriod, flush);
  }

  /// Commits immediately - used when the burst is over for a reason other than
  /// the timer, e.g. the user pressed play or the screen is closing.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending == Duration.zero) return;
    final total = _pending;
    _pending = Duration.zero;
    onSeek(total);
  }

  /// Throws away anything pending without seeking - for when the position is
  /// about to become meaningless anyway (a scrubber drag, a new media).
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = Duration.zero;
  }

  void dispose() => cancel();
}
