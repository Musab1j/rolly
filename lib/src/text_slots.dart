import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import 'keyed_slots.dart';
import 'line_geometry.dart';
import 'slot_keying.dart';

/// How a line of text is cut into the units that animate independently of one another.
enum TextSplit {
  /// One unit per user-perceived character, so a letter and its combining accent, or an emoji and
  /// its modifiers, stay together instead of flying apart.
  ///
  /// A run of joining script is the exception and stays whole — see [_joiningRanges].
  character,

  /// One unit per whitespace-delimited word. The right choice for prose.
  word,
}

/// Identifies the glyphs of arbitrary text by diffing each line against the one before it.
@immutable
class TextKeying extends SlotKeying {
  const TextKeying(this.split);

  final TextSplit split;

  @override
  SlotKeyer createKeyer() => TextSlotKeyer(split);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextKeying && other.split == split;

  @override
  int get hashCode => split.hashCode;
}

/// Assigns identities to the units of successive lines of text.
///
/// A formatted number carries its own structure, so its glyphs can be keyed from one line in
/// isolation — the third integer digit is the third integer digit whatever the previous value was.
/// Text has no such structure, so identity has to be *found*, by diffing the new line against the
/// one on screen. That is the whole difference between this and [NumericKeying], and it is why
/// this keyer is stateful where that one is not.
///
/// Two decisions in the diff decide how the transition reads:
///
/// * **Survivors keep their key.** A unit the diff matches is the same glyph, so it only reflows
///   into its new position. `Saving…` -> `Saved` slides the shared letters rather than rebuilding
///   the word.
/// * **A replaced run is paired off positionally.** Where the diff finds a stretch of the old line
///   deleted and a stretch of the new line inserted in the same place, the two are zipped together
///   from the left and the pairs reuse the old keys — which the engine sees as the same column
///   showing something new, and therefore rolls. Without this, `ON -> OFF` would dissolve `N` and
///   pop `F` in beside it; with it, `N` rolls into `F` and only the second `F` is born. Whichever
///   run is longer spills over into ordinary births or deaths.
class TextSlotKeyer implements SlotKeyer {
  TextSlotKeyer(this.split);

  final TextSplit split;

  /// The previous line, in logical order — which is the order the diff has to run in. Note that
  /// [assign] returns its slots in *visual* order instead, and for bidirectional text the two
  /// genuinely differ.
  List<({String key, String text})> _previous = const [];

  /// Monotonic, and deliberately not reset by [reset]: a freshly minted key must not collide with
  /// one still attached to a column that is in the middle of fading out.
  int _minted = 0;

  @override
  List<KeyedSlot> assign(String text, LineGeometry geometry) {
    assert(
      geometry.text == text,
      'geometry must have been measured from this exact string',
    );

    final units = _splitUnits(text, split);
    final taken = alignUnits(
      [for (final unit in _previous) unit.text],
      [for (final unit in units) unit.text],
    );

    final keys = [
      for (var i = 0; i < units.length; i++)
        if (taken[i] >= 0) _previous[taken[i]].key else _mint(),
    ];

    _previous = [
      for (var i = 0; i < units.length; i++)
        (key: keys[i], text: units[i].text),
    ];

    final slots = <KeyedSlot>[];
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      final (left, right) = geometry.boundsFor(unit.utf16Start, unit.utf16End);
      slots.add(
        KeyedSlot(
          key: keys[i],
          // Everything in a line of text moves under one set of physics and takes part in the
          // cascade. The distinctions the numeric tokenizer draws - separators sitting out the
          // wave, a fraction span taking a second colour - have no counterpart here.
          kind: TokenKind.digit,
          semanticKind: TokenKind.other,
          glyph: unit.text,
          left: left,
          right: right,
          utf16Start: unit.utf16Start,
          utf16End: unit.utf16End,
        ),
      );
    }

    // Screen order, so the left-to-right cascade follows what the eye sees rather than the string's
    // logical order. The two differ for any line containing a right-to-left run.
    slots.sort((a, b) {
      final byCenter = a.center.compareTo(b.center);
      if (byCenter != 0) return byCenter;
      final byLeft = a.left.compareTo(b.left);
      return byLeft != 0 ? byLeft : a.utf16Start.compareTo(b.utf16Start);
    });

    return List.unmodifiable(slots);
  }

  @override
  void reset() => _previous = const [];

  /// Lower case, which keeps these clear of every key [layoutKeyedSlots] mints and, in particular,
  /// out of the fraction span [isFractionKey] recognises.
  String _mint() => 't${_minted++}';
}

/// One unit of a line, and where to find it in the string.
class _Unit {
  const _Unit(this.text, this.utf16Start, this.utf16End);

  final String text;
  final int utf16Start;
  final int utf16End;
}

/// Runs of non-whitespace. `\s` here is ECMAScript's, which covers the Unicode spaces — an Arabic
/// line separated by U+00A0 splits the same way a Latin one separated by U+0020 does.
final _word = RegExp(r'\S+');

List<_Unit> _splitUnits(String text, TextSplit split) {
  switch (split) {
    case TextSplit.word:
      return [
        for (final match in _word.allMatches(text))
          _Unit(match[0]!, match.start, match.end),
      ];

    case TextSplit.character:
      final units = <_Unit>[];
      var offset = 0;
      var previousJoined = false;

      // Spaces become units of their own even though they draw nothing. They hold a column, so the
      // diff can report one being inserted or removed, which is what makes `ab -> a b` read as a
      // gap opening rather than as the whole line being rebuilt.
      for (final cluster in text.characters) {
        final joins = _joins(cluster);
        final end = offset + cluster.length;

        if (joins && previousJoined) {
          // Absorb into the run being built rather than starting a unit of its own.
          final open = units.removeLast();
          units.add(_Unit(open.text + cluster, open.utf16Start, end));
        } else {
          units.add(_Unit(cluster, offset, end));
        }

        previousJoined = joins;
        offset = end;
      }
      return units;
  }
}

/// Whether [cluster] is a letter of a script whose glyphs join to their neighbours.
///
/// Such a letter is shaped by its context: `ل` on its own is `ل`, but between two letters it is a
/// bare vertical stroke. Every unit here is laid out on its own — that is what makes it movable —
/// so cutting between two joining letters would render both in their isolated forms at positions
/// measured for their joined ones. The letters come apart, overlap, and the word stops reading as
/// what it says. Keeping the run whole is not a nicety; there is no correct way to animate the
/// letters of a cursive word separately while each is typeset alone.
bool _joins(String cluster) {
  for (final codePoint in cluster.runes) {
    for (final (start, end) in _joiningRanges) {
      if (codePoint >= start && codePoint <= end) return true;
    }
  }
  return false;
}

/// The joining scripts in common use, as code point ranges.
///
/// Digits and punctuation that share these blocks are deliberately left out — those never join,
/// and folding them in would glue a numeral to the word beside it and stop it animating on its
/// own. This is an approximation of Unicode's `Joining_Type`, chosen to err towards keeping a run
/// together: including one character too many costs an animation boundary, excluding one breaks
/// the word.
const _joiningRanges = <(int, int)>[
  (0x0620, 0x065F), // Arabic letters, and the marks that ride on them
  (0x066E, 0x066F), // dotless beh and qaf
  (0x0670, 0x06D3), // superscript alef through the extended letters
  (0x06D5, 0x06ED), // taa marbuta, then the Quranic annotation marks
  (0x06EE, 0x06EF),
  (0x06FA, 0x06FF),
  (0x0710, 0x074F), // Syriac
  (0x0750, 0x077F), // Arabic Supplement
  (0x07CA, 0x07EA), // N'Ko
  (0x0840, 0x085B), // Mandaic
  (0x0860, 0x086A), // Syriac Supplement
  (0x0870, 0x088E), // Arabic Extended-B
  (0x08A0, 0x08E1), // Arabic Extended-A
  (0x08E3, 0x08FF),
  (0x1807, 0x18AA), // Mongolian
  (0xFB50, 0xFDFF), // Arabic Presentation Forms-A
  (0xFE70, 0xFEFC), // Arabic Presentation Forms-B
  (0x1E900, 0x1E94B), // Adlam
];

/// Above this many cells the quadratic diff is abandoned for positional pairing. A line this long
/// is past the point where any of this reads as an animation anyway, and the guard costs nothing
/// on the lines that are not.
const _maxDiffCells = 1 << 16;

/// Pairs the units of a new line against the previous one.
///
/// Returns, for each unit of [next], the index in [previous] whose identity it takes, or `-1` when
/// it takes none — a unit that is genuinely new, and so is born rather than rolled into.
@visibleForTesting
List<int> alignUnits(List<String> previous, List<String> next) {
  final taken = List<int>.filled(next.length, -1);
  if (previous.isEmpty || next.isEmpty) return taken;

  if (previous.length * next.length > _maxDiffCells) {
    for (var i = 0; i < math.min(previous.length, next.length); i++) {
      taken[i] = i;
    }
    return taken;
  }

  var oldAt = 0;
  var newAt = 0;

  // A sentinel past the end of both lines, so the run trailing the last match is closed out by the
  // same code as every gap before it.
  for (final (i, j) in [
    ..._commonSubsequence(previous, next),
    (previous.length, next.length),
  ]) {
    // What sits between the previous match and this one is a replacement. Zip the two runs
    // together from the left: those pairs reuse a key and therefore roll, and whatever is left
    // over on one side or the other is a birth or a death.
    final paired = math.min(i - oldAt, j - newAt);
    for (var k = 0; k < paired; k++) {
      taken[newAt + k] = oldAt + k;
    }

    if (j < next.length) taken[j] = i;
    oldAt = i + 1;
    newAt = j + 1;
  }

  return taken;
}

/// The longest common subsequence of [a] and [b], as index pairs in increasing order.
List<(int, int)> _commonSubsequence(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;

  // lengths[i][j] is the length of the longest common subsequence of a[i:] and b[j:].
  final lengths = List.generate(
    n + 1,
    (_) => Int32List(m + 1),
    growable: false,
  );
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lengths[i][j] = a[i] == b[j]
          ? lengths[i + 1][j + 1] + 1
          : math.max(lengths[i + 1][j], lengths[i][j + 1]);
    }
  }

  final matches = <(int, int)>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      matches.add((i, j));
      i++;
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return matches;
}
