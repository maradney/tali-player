import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/features/player/resume_guard.dart';

/// Opening an episode saved at 18:00 and having the stream stall used to
/// overwrite that mark with the failure: the 5-second progress timer starts as
/// soon as the screen opens, so a position near zero got written back and the
/// real resume point was gone.
void main() {
  const saved = Duration(minutes: 18);
  const far = Duration(minutes: 19);
  const near = Duration(seconds: 12);

  test('with nothing saved, everything is allowed', () {
    // First watch: there is no mark to protect, so normal saving applies.
    final guard = ResumeGuard(savedPosition: null);
    expect(guard.allowsSaving(near, hasError: false), isTrue);
    expect(guard.isProtecting, isFalse);
  });

  test('a stalled stream cannot overwrite the saved point', () {
    final guard = ResumeGuard(savedPosition: saved);
    // The stream never got going; the timer fires anyway.
    expect(guard.allowsSaving(near, hasError: false), isFalse);
    expect(guard.allowsSaving(Duration.zero, hasError: false), isFalse);
  });

  test('an errored stream never saves, even past the mark', () {
    // A failed stream's position is meaningless whatever its value.
    final guard = ResumeGuard(savedPosition: saved);
    expect(guard.allowsSaving(far, hasError: true), isFalse);
    final fresh = ResumeGuard(savedPosition: null);
    expect(fresh.allowsSaving(far, hasError: true), isFalse);
  });

  test('once the resume seek lands, saving resumes', () {
    final guard = ResumeGuard(savedPosition: saved);
    guard.resumeChosen();
    expect(guard.allowsSaving(near, hasError: false), isFalse);

    guard.observe(saved);
    expect(guard.isProtecting, isFalse);
    // And from then on, ordinary progress - including going backwards, which
    // is just the user rewinding - is saved normally.
    expect(guard.allowsSaving(near, hasError: false), isTrue);
  });

  test('a seek landing slightly short still counts as landed', () {
    // mpv snaps to the nearest keyframe, so the position after a seek is
    // routinely a second or two before the target.
    final guard = ResumeGuard(savedPosition: saved);
    guard.observe(saved - const Duration(seconds: 2));
    expect(guard.isProtecting, isFalse);
  });

  test('landing far short does not count', () {
    final guard = ResumeGuard(savedPosition: saved);
    guard.observe(saved - const Duration(seconds: 30));
    expect(guard.isProtecting, isTrue);
    expect(guard.allowsSaving(near, hasError: false), isFalse);
  });

  test('choosing Start over releases the guard', () {
    // The user explicitly discarded the mark, so overwriting it is the point.
    final guard = ResumeGuard(savedPosition: saved);
    guard.startOverChosen();
    expect(guard.allowsSaving(near, hasError: false), isTrue);
  });

  test('playing past the saved point saves without any prompt answer', () {
    // Covers the case where no resume prompt appeared (or was dismissed) but
    // playback genuinely got further than the mark.
    final guard = ResumeGuard(savedPosition: saved);
    expect(guard.allowsSaving(far, hasError: false), isTrue);
  });
}
