import 'spring.dart';

/// The model behind the transition: four channels, two springs, one cascade.
///
/// A glyph changing is not one animation but four overlapping ones — it moves, it grows, it
/// fades, it comes into focus — and they run on different clocks. The constants below say how.
/// They are tuned against SwiftUI's `.contentTransition(.numericText())` rather than chosen for
/// taste, and `doc/animation_model.md` explains what each one is doing and why it is that number.
///
/// Changing a value here does not tune the animation — it detunes it away from the original.
class NumericTransitionModel {
  const NumericTransitionModel._();

  // ---------------------------------------------------------------------------------------------
  // Channels. Four of them, on two clocks.
  //
  // Position gets its own bouncy spring; scale and alpha share a critically damped one. The
  // split is not an optimisation: offset overshoots and the other two never do, so a single
  // spring cannot produce both.
  // ---------------------------------------------------------------------------------------------

  /// Vertical offset. ζ=0.55, so it overshoots ~12.6% and settles back — an arriving digit
  /// crosses its resting line ~145 ms in and eases back up to it.
  static const SpringResponse offsetSpring = SpringResponse(0.353, 0.55);

  /// Scale. Critically damped: a glyph grows into its size without ever exceeding it.
  static const SpringResponse scaleSpring = SpringResponse(0.278, 1.0);

  /// Opacity. Critically damped, and near enough to [scaleSpring] that size and presence resolve
  /// together. Starting with zero slope is what gives an arriving glyph its brief dead zone
  /// before it becomes perceptible.
  static const SpringResponse alphaSpring = SpringResponse(0.276, 1.0);

  /// Blur. The slowest channel by a wide margin — a glyph is still coming into focus well after
  /// it has stopped moving, which is most of what separates this from a hard digit flip.
  static const SpringResponse blurSpring = SpringResponse(0.398, 0.91);

  // ---------------------------------------------------------------------------------------------
  // Amplitudes, in glyph heights.
  // ---------------------------------------------------------------------------------------------

  /// How far along the roll axis an arriving glyph starts, in glyph heights.
  ///
  /// This is a fixed *entry offset*, not the spacing between two stops on a drum: a column going
  /// 4 -> 6 enters from exactly as far away as one going 4 -> 5, which is why a jump of 8 reads
  /// the same as a jump of 1. Treating it as inter-digit spacing is a natural guess and gives
  /// the wrong motion entirely.
  static const double entryOffset = 0.59375;

  /// The scale a glyph is born at and dies at.
  ///
  /// Carried at full precision; it is very close to 51/128, which is suggestive of a
  /// fixed-point constant in the original.
  static const double bornScale = 0.3984375;

  /// Peak blur sigma, in glyph heights, reached at the moment of birth or death.
  static const double maxBlurSigma = 0.125;

  // ---------------------------------------------------------------------------------------------
  // The cascade.
  // ---------------------------------------------------------------------------------------------

  /// Total time the left-to-right cascade is spread over, regardless of how many columns change.
  ///
  /// It is a fixed budget, not a per-column delay: two changing columns are 150 ms apart, five are
  /// 37.5 ms apart. The leader always starts at zero. This is why a long number does not take
  /// proportionally longer to transition.
  static const double cascadeTotalSeconds = 0.15;

  /// How long a surviving glyph takes to slide between its old and new horizontal positions when
  /// the line's width changes.
  ///
  /// Critically damped, and it starts moving on the very first frame — the reflow is a slow ease,
  /// not a delay followed by a slide.
  static const SpringResponse reflowSpring = SpringResponse(0.22, 1.0);

  /// The duration all four channels are scaled against. A `duration` of 320 ms runs the
  /// transition as designed; anything else stretches every channel by the same factor.
  static const double referenceDurationMs = 320.0;

  // ---------------------------------------------------------------------------------------------
  // Render thresholds.
  // ---------------------------------------------------------------------------------------------

  /// Below this alpha a glyph is dropped from the stack entirely.
  static const double cullAlpha = 0.004;

  /// Below this alpha a glyph is not drawn, but is still tracked.
  static const double renderAlphaEpsilon = 0.01;

  /// Blur sigmas below this are rounded to zero, skipping the layer entirely.
  static const double minRenderSigma = 0.05;

  /// Sigma quantisation step for the blur-layer cache, in device pixels. Fine enough to be
  /// invisible, coarse enough that consecutive frames usually hit the same bucket.
  static const double sigmaQuantum = 0.25;
}

/// Which way the glyphs roll.
enum NumericDirection {
  /// Decided per transition by whether the number grew or shrank. Almost always what you want.
  automatic,

  /// Always roll as though the number increased, whatever it actually did.
  up,

  /// Always roll as though the number decreased.
  down,
}

/// Whether to honour the platform's reduced-motion setting.
enum NumericReduceMotion {
  /// Follow `MediaQuery.disableAnimations`.
  system,

  /// Never animate; snap to each new value.
  always,

  /// Always animate, even when the platform asks for reduced motion. Use sparingly.
  never,
}

/// What a glyph is doing, which decides which set of curves it runs.
enum GlyphRole {
  /// Settled, or rolling in to replace a glyph in the same column.
  arriving,

  /// Rolling out, replaced by another glyph in the same column.
  departing,

  /// Born because the column itself is new — `999` gaining a fourth digit. Appears in place at
  /// [NumericTransitionModel.bornScale], blurred, and grows. Crucially it has *no* vertical
  /// entry; that is the whole difference between a structural change and a roll.
  enteringStructural,

  /// Dying because the column itself is going away. Shrinks and blurs out in place.
  exitingStructural,
}
