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
