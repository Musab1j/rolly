import 'package:flutter/foundation.dart';

import 'line_geometry.dart';

/// What a glyph means in the formatted number.
enum TokenKind {
  digit,
  groupSeparator,
  decimalSeparator,
  sign,

  /// Anything else that is drawn: a currency symbol, a percent sign, an accounting bracket.
  other,
}

/// One glyph of a laid-out line, with the identity that lets it be matched against the same glyph
/// in a different line.
@immutable
class KeyedSlot {
  const KeyedSlot({
    required this.key,
    required this.kind,
    required this.semanticKind,
    required this.glyph,
    required this.left,
    required this.right,
    required this.utf16Start,
    required this.utf16End,
  });

  /// The identity this glyph is matched on across values. Two slots with the same key in the old
  /// and new line are *the same glyph*, and animate as a roll; a key present in only one of them
  /// is a birth or a death.
  final String key;

  /// Which set of physics this glyph moves under. Signs and affixes are deliberately reported as
  /// [TokenKind.digit] here so they roll exactly like digits do; [semanticKind] keeps what they
  /// actually are.
  final TokenKind kind;

  /// What the glyph actually is, independent of how it moves.
  final TokenKind semanticKind;

  /// The text drawn in this slot, and the thing compared to decide whether the slot's contents
  /// changed. Usually a single character; a slot can hold a whole word when the line is split that
  /// way — see `text_slots.dart`.
  final String glyph;

  /// Horizontal bounds, measured from the left edge of the typeset line.
  final double left;
  final double right;

  final int utf16Start;
  final int utf16End;

  double get center => (left + right) / 2;
}

/// Directional formatting marks: present in the string and part of shaping, but with no glyph of
/// their own, so they never become animated slots.
bool _isDirectionalMark(int codePoint) =>
    codePoint == 0x061C || codePoint == 0x200E || codePoint == 0x200F;

/// Whether [key] belongs to the fraction span - the decimal mark, the digits after it, and any
/// trailing affix. This is the span a second colour tints.
bool isFractionKey(String key) =>
    key.startsWith('F') || key.startsWith('DEC') || key.startsWith('X');

class _RawToken {
  _RawToken(this.text, this.codePoint, this.utf16Start, this.utf16End);
  final String text;
  final int codePoint;
  final int utf16Start;
  final int utf16End;
}

class _Token {
  _Token(this.raw, this.kind, this.fractional);
  final _RawToken raw;
  final TokenKind kind;
  final bool fractional;
}

/// Splits [text] into code points, keeping each one's UTF-16 range so it can be located in the
/// laid-out line.
List<_RawToken> _rawTokens(String text) {
  final out = <_RawToken>[];
  var offset = 0;
  for (final codePoint in text.runes) {
    final char = String.fromCharCode(codePoint);
    out.add(_RawToken(char, codePoint, offset, offset + char.length));
    offset += char.length;
  }
  return out;
}

/// Assigns every glyph in a formatted number a stable identity, and reports where it sits.
///
/// The keys are the whole trick. A transition is a diff of two of these lists, so what counts as
/// "the same glyph" is decided entirely here, and each rule exists to stop a specific ugly
/// behaviour:
///
/// * **Integer digits are numbered from the left, fraction digits from the decimal mark.** A
///   fraction digit anchored from the left edge would change identity whenever the integer part
///   grew, so `9.75 -> 10.75` would pointlessly re-roll the cents.
/// * **Group separators are keyed by how many integer digits sit to their right**, not by
///   position. The comma in `1,000` and the second comma in `1,000,000` are both "the comma with
///   three digits after it", so growing a number slides its existing commas outward instead of
///   destroying and rebuilding them.
/// * **Affixes are keyed by their distance from the digits, measured visually.** A `$` is "the
///   first thing left of the number" whether the number is 3 digits or 7, so `$999 -> $1,000`
///   moves one symbol rather than flashing a new one into place.
///
/// [groupSeparator], [decimalSeparator] and [minusSign] must come from the locale actually in
/// use; the classification is wrong otherwise, since a comma is a decimal mark in half of Europe.
List<KeyedSlot> layoutKeyedSlots({
  required String formatted,
  required LineGeometry geometry,
  required String groupSeparator,
  required String decimalSeparator,
  required String minusSign,
  String zeroDigit = '0',
}) {
  assert(
    geometry.text == formatted,
    'geometry must have been measured from this exact string',
  );

  final tokens = _tokenize(
    formatted,
    groupSeparator: groupSeparator,
    decimalSeparator: decimalSeparator,
    minusSign: minusSign,
    zeroDigit: zeroDigit,
  ).where((token) => !_isDirectionalMark(token.raw.codePoint)).toList();

  if (tokens.isEmpty) return const [];

  // How many integer digits sit to the right of each token - the group separators' identity.
  final integerDigitsToRight = List<int>.filled(tokens.length, 0);
  var running = 0;
  for (var i = tokens.length - 1; i >= 0; i--) {
    integerDigitsToRight[i] = running;
    if (tokens[i].kind == TokenKind.digit && !tokens[i].fractional) running++;
  }

  final bounds = [
    for (final token in tokens)
      geometry.boundsFor(token.raw.utf16Start, token.raw.utf16End),
  ];

  // The visual extent of the digits, which is what affixes are ranked against.
  double? numericLeft;
  double? numericRight;
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].kind != TokenKind.digit) continue;
    final (left, right) = bounds[i];
    numericLeft = numericLeft == null
        ? left
        : (left < numericLeft ? left : numericLeft);
    numericRight = numericRight == null
        ? right
        : (right > numericRight ? right : numericRight);
  }

  final prefixRank = List<int>.filled(tokens.length, -1);
  final suffixRank = List<int>.filled(tokens.length, -1);

  if (numericLeft != null && numericRight != null) {
    const epsilon = 0.001;

    // Ranked by distance from the digits rather than by string order, because the two can
    // disagree: a currency code can follow the digits logically while rendering to their left.
    // Keying such a token as a suffix would match it against a former visual suffix and send the
    // column travelling horizontally across the whole number.
    final prefixes = [
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i].kind == TokenKind.other &&
            bounds[i].$2 <= numericLeft + epsilon)
          i,
    ]..sort((a, b) => bounds[b].$1.compareTo(bounds[a].$1));
    for (var rank = 0; rank < prefixes.length; rank++) {
      prefixRank[prefixes[rank]] = rank;
    }

    final suffixes = [
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i].kind == TokenKind.other &&
            bounds[i].$1 >= numericRight - epsilon)
          i,
    ]..sort((a, b) => bounds[a].$1.compareTo(bounds[b].$1));
    for (var rank = 0; rank < suffixes.length; rank++) {
      suffixRank[suffixes[rank]] = rank;
    }
  }

  final slots = <KeyedSlot>[];
  var integerPosition = 0;
  var fractionPosition = 0;

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final key = switch (token.kind) {
      TokenKind.digit =>
        token.fractional ? 'F${fractionPosition++}' : 'I${integerPosition++}',
      TokenKind.groupSeparator =>
        'G${integerDigitsToRight[i]}:${token.raw.text}',
      TokenKind.decimalSeparator => 'DEC:${token.raw.text}',
      TokenKind.sign => 'S',
      TokenKind.other => switch ((prefixRank[i], suffixRank[i])) {
        (final p, _) when p >= 0 => 'P$p',
        (_, final s) when s >= 0 => 'X$s',
        // Wedged between digits, which formatting should not produce; fall back to position so it
        // at least stays put instead of colliding with another key.
        _ => 'O$i',
      },
    };

    // Signs and affixes move under digit physics. They were validated as part of the same roll,
    // so giving them their own would make a currency symbol animate differently from the number
    // it belongs to.
    final physicsKind = switch (token.kind) {
      TokenKind.sign || TokenKind.other => TokenKind.digit,
      _ => token.kind,
    };

    slots.add(
      KeyedSlot(
        key: key,
        kind: physicsKind,
        semanticKind: token.kind,
        glyph: token.raw.text,
        left: bounds[i].$1,
        right: bounds[i].$2,
        utf16Start: token.raw.utf16Start,
        utf16End: token.raw.utf16End,
      ),
    );
  }

  // Screen order, so the left-to-right cascade follows what the eye sees even when the string's
  // logical order differs.
  slots.sort((a, b) {
    final byCenter = a.center.compareTo(b.center);
    if (byCenter != 0) return byCenter;
    final byLeft = a.left.compareTo(b.left);
    return byLeft != 0 ? byLeft : a.utf16Start.compareTo(b.utf16Start);
  });

  return List.unmodifiable(slots);
}

List<_Token> _tokenize(
  String text, {
  required String groupSeparator,
  required String decimalSeparator,
  required String minusSign,
  required String zeroDigit,
}) {
  final raw = _rawTokens(text);
  if (raw.isEmpty) return const [];

  final zero = zeroDigit.runes.first;
  bool isDigit(int codePoint) =>
      (codePoint >= 0x30 && codePoint <= 0x39) ||
      (codePoint >= zero && codePoint <= zero + 9);

  bool matches(_RawToken token, String separator) =>
      separator.isNotEmpty && token.text == separator;

  final firstDigit = raw.indexWhere((t) => isDigit(t.codePoint));
  final lastDigit = raw.lastIndexWhere((t) => isDigit(t.codePoint));

  // The decimal mark is the last one sitting between the digits, or one immediately after them
  // (a format can render a trailing mark with no fraction digits). Anything else that looks like
  // a decimal mark is part of an affix, not the number.
  var decimalIndex = -1;
  if (firstDigit >= 0) {
    for (var i = firstDigit + 1; i < lastDigit; i++) {
      if (matches(raw[i], decimalSeparator)) decimalIndex = i;
    }
    if (decimalIndex < 0 &&
        lastDigit + 1 < raw.length &&
        matches(raw[lastDigit + 1], decimalSeparator)) {
      decimalIndex = lastDigit + 1;
    }
  }

  final integerEnd = decimalIndex >= 0 ? decimalIndex : lastDigit + 1;

  bool hasDigitBefore(int index) {
    for (var i = index - 1; i >= firstDigit; i--) {
      if (isDigit(raw[i].codePoint)) return true;
      if (!_isDirectionalMark(raw[i].codePoint)) return false;
    }
    return false;
  }

  bool hasDigitAfter(int index) {
    for (var i = index + 1; i < integerEnd; i++) {
      if (isDigit(raw[i].codePoint)) return true;
      if (!_isDirectionalMark(raw[i].codePoint)) return false;
    }
    return false;
  }

  // A minus is only a sign if it is outside the digits. One between letters belongs to an affix.
  bool isSignPosition(int index) {
    if (firstDigit < 0 || (index >= firstDigit && index <= lastDigit)) {
      return false;
    }
    final before = index > 0 ? raw[index - 1].codePoint : null;
    final after = index + 1 < raw.length ? raw[index + 1].codePoint : null;
    final betweenLetters =
        before != null &&
        after != null &&
        _isLetter(before) &&
        _isLetter(after);
    return !betweenLetters;
  }

  TokenKind kindOf(int i) {
    final token = raw[i];
    if (isDigit(token.codePoint)) return TokenKind.digit;
    if (i == decimalIndex) return TokenKind.decimalSeparator;

    // A grouping mark only counts as one when it actually sits between integer digits. The same
    // character elsewhere in the line belongs to an affix.
    if (firstDigit >= 0 &&
        i > firstDigit &&
        i < integerEnd &&
        matches(token, groupSeparator) &&
        hasDigitBefore(i) &&
        hasDigitAfter(i)) {
      return TokenKind.groupSeparator;
    }

    if (matches(token, minusSign) && isSignPosition(i)) return TokenKind.sign;
    return TokenKind.other;
  }

  return [
    for (var i = 0; i < raw.length; i++)
      _Token(
        raw[i],
        kindOf(i),
        isDigit(raw[i].codePoint) && decimalIndex >= 0 && i > decimalIndex,
      ),
  ];
}

/// ASCII letters only. This exists to spot a minus embedded in a textual affix (`EUR-USD`), and
/// widening it to all non-ASCII would misread currency symbols like `€` as letters.
bool _isLetter(int codePoint) =>
    (codePoint >= 0x41 && codePoint <= 0x5A) ||
    (codePoint >= 0x61 && codePoint <= 0x7A);
