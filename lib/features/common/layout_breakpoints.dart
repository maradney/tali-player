/// Width at or above which the UI uses its desktop shape: a navigation rail
/// instead of a bottom bar, and a category rail beside its content instead of
/// a collapsed selector.
///
/// One constant for both so a window can never end up half-converted - a
/// phone-style bottom bar next to a 240px desktop category rail, which is what
/// the Android port originally shipped because only the shell was responsive.
///
/// 700 is chosen so a phone stays narrow in both orientations (a large phone
/// is ~410dp portrait, ~915dp landscape, but a rail there would eat a quarter
/// of the video-browsing width) while a real desktop window is always wide.
const kWideLayoutBreakpoint = 700.0;

/// Whether [width] gets the desktop shape. Takes the window's width, not a
/// widget's own constraints - inside the shell body the navigation rail has
/// already been subtracted, which would flip the answer on a borderline window.
bool isWideLayout(double width) => width >= kWideLayoutBreakpoint;

/// Whether the Home dashboard shows its search pill.
///
/// Phone-only, and expressed here rather than as an inline comparison so
/// "this changes nothing on desktop" is something a test can actually assert.
bool showsHomeSearchPill(double width) => !isWideLayout(width);
