/// Decides whether a playback position is safe to persist as the resume point.
///
/// The player saves progress on a 5-second timer that starts as soon as the
/// screen opens, before anything is known about whether the stream actually
/// loaded. That is fine until there is already a resume point to protect: open
/// an episode saved at 18:00, have the stream stall or fail, and playback sits
/// near zero while the timer keeps firing - so the position that gets written
/// back is the failure, and 18:00 is gone. Losing the mark is worse than any
/// buffering, because the buffering is temporary and the mark is not.
///
/// The rule is that a *smaller* position may only overwrite a larger saved one
/// once we have seen playback actually reach the saved point, or once the user
/// has said to start over. Growing positions always save, which is the normal
/// case and stays untouched.
class ResumeGuard {
  ResumeGuard({required this.savedPosition});

  /// The position already on record when this item was opened, if any. Null
  /// means there is nothing to protect and every save is allowed.
  final Duration? savedPosition;

  bool _reached = false;
  bool _startOver = false;

  /// The user answered "Start over" on the resume prompt, so the old mark is
  /// theirs to discard.
  void startOverChosen() => _startOver = true;

  /// The user answered "Resume": the seek is on its way but has not
  /// necessarily landed, so the mark still needs protecting until it does.
  void resumeChosen() => _reached = false;

  /// Feed every position update in. Once playback has genuinely arrived at (or
  /// past) the saved point, the guard steps aside for the rest of the session.
  void observe(Duration position) {
    final saved = savedPosition;
    if (saved == null) return;
    // A small tolerance because a seek rarely lands on the exact millisecond -
    // mpv snaps to the nearest keyframe, which can be a second or two short.
    if (position + const Duration(seconds: 3) >= saved) _reached = true;
  }

  /// Whether [position] may be written as the new resume point.
  ///
  /// [hasError] blocks saving outright: a stream that failed has no meaningful
  /// position, and its zero is exactly what destroys the mark.
  bool allowsSaving(Duration position, {required bool hasError}) {
    if (hasError) return false;
    final saved = savedPosition;
    if (saved == null) return true;
    if (_startOver || _reached) return true;
    // Still short of the mark and nobody has chosen to discard it: only let a
    // position through if it is already further along than what is saved.
    return position > saved;
  }

  /// Exposed for tests and for the "finished" branch, which clears the entry
  /// entirely rather than saving a position.
  bool get isProtecting => savedPosition != null && !_reached && !_startOver;
}
