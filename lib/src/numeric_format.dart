import 'package:flutter/foundation.dart';

/// How a number is turned into the line of glyphs that gets animated.
///
/// This is a value type: two formats built with the same arguments compare equal, so the widget
/// can tell an actual format change (which is a structural transition — a currency symbol
/// appearing, the decimal point moving) from a rebuild that happened to construct a new instance.
///
/// The formatter is self-contained, which is why this package depends on nothing. It covers the
/// shapes a rolling number is usually in — plain, grouped, currency, percent — and takes its
/// separators as arguments rather than from locale data:
///
/// ```dart
/// // 1.234,50 — German conventions, no locale database involved.
/// const NumericTextFormat.decimal(
///   groupSeparator: '.',
///   decimalSeparator: ',',
///   minimumFractionDigits: 2,
///   maximumFractionDigits: 2,
/// )
/// ```
///
/// For real locale data — currency symbols per country, non-Western numerals, accounting
/// notation — hand [NumericTextFormat.custom] any formatting function you like, `intl`'s
/// included:
///
/// ```dart
/// final de = NumberFormat.currency(locale: 'de_DE');
/// NumericTextFormat.custom(
///   de.format,
///   groupSeparator: de.symbols.GROUP_SEP,
///   decimalSeparator: de.symbols.DECIMAL_SEP,
///   minusSign: de.symbols.MINUS_SIGN,
/// );
/// ```
///
/// Whichever route you take, [groupSeparator] and [decimalSeparator] have to match what [format]
/// actually produces. The tokenizer classifies glyphs by comparing them against those two
/// strings, and in half of Europe a comma is a *decimal* mark — get them wrong and the number
/// animates its decimal point as though it were a thousands separator.
@immutable
class NumericTextFormat {
  /// A plain number: `1,234` or `1,234.50`.
  const NumericTextFormat.decimal({
    this.minimumFractionDigits = 0,
    this.maximumFractionDigits = 3,
    this.useGrouping = true,
    this.groupSeparator = ',',
    this.decimalSeparator = '.',
    this.minusSign = '-',
    this.zeroDigit = '0',
  }) : prefix = '',
       suffix = '',
       multiplier = 1,
       _formatter = null;

  /// A whole number: `1,234`.
  const NumericTextFormat.integer({
    bool useGrouping = true,
    String groupSeparator = ',',
    String minusSign = '-',
    String zeroDigit = '0',
  }) : this.decimal(
         minimumFractionDigits: 0,
         maximumFractionDigits: 0,
         useGrouping: useGrouping,
         groupSeparator: groupSeparator,
         minusSign: minusSign,
         zeroDigit: zeroDigit,
       );

  /// An amount: `$1,234.50`. The symbol keeps its identity across magnitude changes, so
  /// `$999 -> $1,000` slides the `$` left rather than destroying and recreating it.
  ///
  /// A negative amount puts the sign outermost — `-$1,234.50` — so the symbol stays where it is
  /// when the value crosses zero.
  const NumericTextFormat.currency({
    String symbol = r'$',
    int decimalDigits = 2,
    bool symbolOnRight = false,
    this.useGrouping = true,
    this.groupSeparator = ',',
    this.decimalSeparator = '.',
    this.minusSign = '-',
    this.zeroDigit = '0',
  }) : prefix = symbolOnRight ? '' : symbol,
       suffix = symbolOnRight ? symbol : '',
       minimumFractionDigits = decimalDigits,
       maximumFractionDigits = decimalDigits,
       multiplier = 1,
       _formatter = null;

  /// A proportion rendered as a percentage: `0.125` formats as `12.5%`.
  const NumericTextFormat.percent({
    this.minimumFractionDigits = 0,
    this.maximumFractionDigits = 1,
    this.useGrouping = true,
    this.groupSeparator = ',',
    this.decimalSeparator = '.',
    this.minusSign = '-',
    this.zeroDigit = '0',
    String symbol = '%',
  }) : prefix = '',
       suffix = symbol,
       multiplier = 100,
       _formatter = null;

  /// Any formatting function at all, for what the built-in formatter does not cover — locale
  /// databases, compact notation, hand-rolled unit suffixes.
  ///
  /// The separators are not cosmetic here: they are what the tokenizer classifies glyphs
  /// against, so they have to be the ones [formatter] emits.
  const NumericTextFormat.custom(
    String Function(num value) formatter, {
    this.groupSeparator = ',',
    this.decimalSeparator = '.',
    this.minusSign = '-',
    this.zeroDigit = '0',
  }) : _formatter = formatter,
       minimumFractionDigits = 0,
       maximumFractionDigits = 0,
       useGrouping = true,
       prefix = '',
       suffix = '',
       multiplier = 1;

  /// The fewest digits shown after the decimal mark. A shorter result is padded with zeros.
  final int minimumFractionDigits;

  /// The most digits shown after the decimal mark. The value is rounded to fit, and trailing
  /// zeros beyond [minimumFractionDigits] are trimmed.
  final int maximumFractionDigits;

  /// Whether the integer part is broken into groups of three by [groupSeparator].
  final bool useGrouping;

  /// The thousands separator. Empty when this format has none.
  final String groupSeparator;

  /// The decimal mark.
  final String decimalSeparator;

  /// The negative sign. Not always ASCII `-`: several conventions use U+2212.
  final String minusSign;

  /// The digit zero this format writes in. Set it to `٠` (U+0660) or `०` (U+0966) to render
  /// Arabic-Indic or Devanagari numerals; the other nine digits follow from it, and the
  /// tokenizer recognises them as digits.
  final String zeroDigit;

  /// Written before the digits, inside the sign.
  final String prefix;

  /// Written after the digits.
  final String suffix;

  /// What the value is multiplied by before it is written — 100 for a percentage.
  final num multiplier;

  final String Function(num value)? _formatter;

  /// Renders [value] as the line of glyphs that gets animated.
  String format(num value) {
    final formatter = _formatter;
    if (formatter != null) return formatter(value);

    final scaled = value * multiplier;

    // Nothing below has anything to say about these, and `toStringAsFixed` gives them back as
    // words rather than digits, so they pass straight through.
    if (scaled.isNaN || scaled.isInfinite) return '$prefix$scaled$suffix';

    var negative = scaled.isNegative;
    // `abs()` rather than negation, so -0.0 becomes 0.0 and does not carry its sign into
    // `toStringAsFixed`.
    final magnitude = scaled.abs();

    // `toStringAsFixed` switches to exponent notation from 1e21 up, which has no groups to break
    // and no decimal mark to find. A number that long does not read as a rolling line anyway.
    if (magnitude >= 1e21) {
      return '${negative ? minusSign : ''}$prefix$magnitude$suffix';
    }

    final fixed = magnitude.toStringAsFixed(maximumFractionDigits.clamp(0, 20));
    final dot = fixed.indexOf('.');
    final integerPart = dot == -1 ? fixed : fixed.substring(0, dot);
    var fractionPart = dot == -1 ? '' : fixed.substring(dot + 1);

    // Rounding always produces the maximum number of digits; a trailing zero past the minimum is
    // one nobody asked for.
    while (fractionPart.length > minimumFractionDigits &&
        fractionPart.endsWith('0')) {
      fractionPart = fractionPart.substring(0, fractionPart.length - 1);
    }

    // The sign is decided after rounding, not before: -0.001 shown to two places is `0.00`, and a
    // minus in front of a zero is both wrong and a glyph that would roll in and back out again as
    // the value crosses zero.
    if (negative &&
        !integerPart.contains(RegExp('[1-9]')) &&
        !fractionPart.contains(RegExp('[1-9]'))) {
      negative = false;
    }

    final buffer = StringBuffer();
    if (negative) buffer.write(minusSign);
    buffer
      ..write(prefix)
      ..write(_group(integerPart));
    if (fractionPart.isNotEmpty) {
      buffer
        ..write(decimalSeparator)
        ..write(fractionPart);
    }
    buffer.write(suffix);

    final line = buffer.toString();
    return zeroDigit == '0' ? line : _translateDigits(line);
  }

  /// Breaks the integer digits into groups of three from the right: `1234567` -> `1,234,567`.
  String _group(String digits) {
    if (!useGrouping || groupSeparator.isEmpty || digits.length <= 3) {
      return digits;
    }

    final buffer = StringBuffer();
    final firstGroup = digits.length % 3 == 0 ? 3 : digits.length % 3;
    buffer.write(digits.substring(0, firstGroup));
    for (var i = firstGroup; i < digits.length; i += 3) {
      buffer
        ..write(groupSeparator)
        ..write(digits.substring(i, i + 3));
    }
    return buffer.toString();
  }

  /// Shifts ASCII digits into the block [zeroDigit] belongs to. Every decimal digit block in
  /// Unicode is ten contiguous code points in ascending order, so the offset from zero is all it
  /// takes.
  String _translateDigits(String line) {
    final offset = zeroDigit.runes.first - 0x30;
    return String.fromCharCodes([
      for (final code in line.runes)
        if (code >= 0x30 && code <= 0x39) code + offset else code,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NumericTextFormat &&
          other._formatter == _formatter &&
          other.minimumFractionDigits == minimumFractionDigits &&
          other.maximumFractionDigits == maximumFractionDigits &&
          other.useGrouping == useGrouping &&
          other.groupSeparator == groupSeparator &&
          other.decimalSeparator == decimalSeparator &&
          other.minusSign == minusSign &&
          other.zeroDigit == zeroDigit &&
          other.prefix == prefix &&
          other.suffix == suffix &&
          other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(
    _formatter,
    minimumFractionDigits,
    maximumFractionDigits,
    useGrouping,
    groupSeparator,
    decimalSeparator,
    minusSign,
    zeroDigit,
    prefix,
    suffix,
    multiplier,
  );
}
