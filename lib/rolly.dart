/// Numbers and text that animate the way they do on iOS.
///
/// A Flutter take on SwiftUI's `.contentTransition(.numericText())`: digits roll, the line
/// reflows around them, and glyphs that appear or disappear are born and die in place.
///
/// The animation model — four channels on two springs, a left-to-right cascade on a fixed
/// budget, structural births and deaths, and interruption as a stack of transitions that are
/// never cancelled — is described in `doc/animation_model.md`.
///
/// [NumericText] animates a number; [RollingText] runs the same transition over arbitrary text.
/// They differ in one thing only — how a glyph is recognised across a change — and share
/// everything else.
library;

export 'src/numeric_format.dart' show NumericTextFormat;
export 'src/numeric_text_widget.dart' show NumericText;
export 'src/rolling_text_widget.dart' show RollingText;
export 'src/text_slots.dart' show TextSplit;
export 'src/transition_model.dart' show NumericDirection, NumericReduceMotion;
