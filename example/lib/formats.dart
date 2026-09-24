import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:rolly/rolly.dart';

/// Picks a magnitude first, then a value inside it.
///
/// Drawing uniformly from one big range would land in the top decade almost every time, so nearly
/// every jump would have the same digit count and never exercise a structural change. Choosing the
/// number of digits first makes `7 -> 4,918,204 -> 62` as likely as anything else, which is the
/// interesting case: whole columns born and dying at once, and a line whose width changes a lot.
double _randomMagnitude(
  math.Random random, {
  required int maxDigits,
  int decimals = 0,
}) {
  final digits = 1 + random.nextInt(maxDigits);
  final value = random.nextDouble() * math.pow(10, digits);
  // A quarter of them negative, so the sign column gets born and destroyed too.
  final signed = random.nextInt(4) == 0 ? -value : value;
  return double.parse(signed.toStringAsFixed(decimals));
}

/// One worked example of a shape of number, with a step size that suits it.
@immutable
class FormatPreset {
  const FormatPreset({
    required this.label,
    required this.note,
    required this.format,
    required this.step,
    required this.initial,
    required this.randomValue,
    this.tintFraction = false,
  });

  /// What the chip says.
  final String label;

  /// What this preset is here to show.
  final String note;

  final NumericTextFormat format;

  /// How much one press of the stepper moves the value.
  final double step;

  /// Where this preset starts, chosen so a few presses reach a structural change.
  final double initial;

  /// A value of deliberately unpredictable magnitude, for showing what a large gap does.
  ///
  /// Worth watching: the arriving glyph enters from a *fixed* distance however far the number
  /// jumped, so `7 -> 4,918,204` rolls each surviving column exactly as far as `7 -> 8` would.
  /// The drama all comes from the columns being born, not from the size of the gap.
  final double Function(math.Random random) randomValue;

  /// Whether the fraction span gets a second colour.
  final bool tintFraction;
}

/// The presets the playground offers, each exercising a different part of the model.
final formatPresets = <FormatPreset>[
  // Plain digits and one grouping mark: crossing 999 -> 1,000 births both a digit and a comma.
  FormatPreset(
    label: 'Integer',
    note: 'Crossing 999 births a digit and a comma at once.',
    format: const NumericTextFormat.integer(),
    step: 1,
    initial: 1992,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 7),
  ),

  // A leading affix that has to survive the line getting wider, plus a fraction span that keeps
  // its own identity - stepping by a dollar must not re-roll the cents.
  FormatPreset(
    label: 'Currency',
    note: r'The $ slides rather than flashing, and the cents hold still.',
    format: const NumericTextFormat.currency(),
    step: 1,
    initial: 998.5,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 6, decimals: 2),
    tintFraction: true,
  ),

  // A trailing affix, and a value whose displayed digits move much faster than the raw number.
  FormatPreset(
    label: 'Percent',
    note: 'A trailing affix, and digits that move faster than the value.',
    format: const NumericTextFormat.percent(minimumFractionDigits: 1),
    step: 0.001,
    initial: 0.978,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 4, decimals: 3) / 100,
  ),

  // Mostly fraction digits, so the cascade is long and easy to watch.
  FormatPreset(
    label: 'Decimal',
    note: 'Mostly fraction digits, so the cascade is long and easy to read.',
    format: const NumericTextFormat.decimal(
      minimumFractionDigits: 3,
      maximumFractionDigits: 3,
    ),
    step: 0.001,
    initial: 9.996,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 4, decimals: 3),
  ),

  // Same digits, swapped separators: '.' groups and ',' is the decimal mark. Proof the tokenizer
  // reads the separators off the format rather than assuming en-US.
  FormatPreset(
    label: 'European',
    note:
        "'.' groups and ',' is the decimal mark - and it still animates right.",
    format: const NumericTextFormat.decimal(
      groupSeparator: '.',
      decimalSeparator: ',',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    ),
    step: 1,
    initial: 998.5,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 6, decimals: 2),
    tintFraction: true,
  ),

  // Any formatter at all. This one is a closure; `intl`'s NumberFormat.format drops in the same
  // way, which is how you get locale data without the package depending on it.
  FormatPreset(
    label: 'Custom',
    note: 'Any formatter you like - here, a compact one written by hand.',
    format: NumericTextFormat.custom(_compact),
    step: 1000,
    initial: 964000,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 9),
  ),

  // Digits from another Unicode block, which the tokenizer recognises as digits.
  FormatPreset(
    label: 'Arabic-Indic',
    note: 'Digits from another Unicode block, keyed exactly the same way.',
    format: const NumericTextFormat.integer(zeroDigit: '٠'),
    step: 1,
    initial: 1446,
    randomValue: (r) => _randomMagnitude(r, maxDigits: 6),
  ),
];

/// `12,400 -> 12.4K`. A plain function, to make the point that [NumericTextFormat.custom] takes
/// anything: a closure, a method, or `intl`'s `NumberFormat(...).format`.
String _compact(num value) {
  final magnitude = value.abs();
  final sign = value < 0 ? '-' : '';
  if (magnitude >= 1000000) {
    return '$sign${(magnitude / 1000000).toStringAsFixed(1)}M';
  }
  if (magnitude >= 1000) {
    return '$sign${(magnitude / 1000).toStringAsFixed(1)}K';
  }
  return '$sign${magnitude.round()}';
}
