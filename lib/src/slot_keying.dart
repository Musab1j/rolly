import 'package:flutter/foundation.dart';

import 'keyed_slots.dart';
import 'line_geometry.dart';
import 'numeric_format.dart';

/// Assigns every glyph of a line the identity it will be matched on against the next line.
///
/// This is the one thing that differs between animating a number and animating arbitrary text.
/// Everything downstream — the cascade, the springs, births and deaths, interruption — is a
/// consequence of the keys, and works identically either way.
///
/// A keyer may be stateful. Numeric keys are absolute, derived from the formatted line alone, so
/// [NumericKeying]'s keyer remembers nothing; text has no such structure to key on, so
/// [TextKeying]'s keyer keys each line *against the one before it* and therefore does.
abstract class SlotKeyer {
  /// Keys the glyphs of [text], which must be the string [geometry] was measured from.
  List<KeyedSlot> assign(String text, LineGeometry geometry);

  /// Forgets any history, so the next line is keyed as though it were the first.
  ///
  /// Called whenever the line is installed without animating — the first value, a style change,
  /// reduced motion — so that a keyer's memory can never outlive the glyphs it describes.
  void reset();
}

/// An immutable description of how a line's glyphs are identified.
///
/// Compared with `==`, so a rebuild that produces an equal description keeps the live [SlotKeyer],
/// and whatever history it holds, intact. Only a genuine change builds a new one.
@immutable
abstract class SlotKeying {
  const SlotKeying();

  SlotKeyer createKeyer();
}

/// Identifies glyphs by their place in a formatted number: see [layoutKeyedSlots].
@immutable
class NumericKeying extends SlotKeying {
  const NumericKeying(this.format);

  final NumericTextFormat format;

  @override
  SlotKeyer createKeyer() => _NumericKeyer(format);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NumericKeying && other.format == format;

  @override
  int get hashCode => format.hashCode;
}

class _NumericKeyer implements SlotKeyer {
  _NumericKeyer(this.format);

  final NumericTextFormat format;

  @override
  List<KeyedSlot> assign(String text, LineGeometry geometry) =>
      layoutKeyedSlots(
        formatted: text,
        geometry: geometry,
        groupSeparator: format.groupSeparator,
        decimalSeparator: format.decimalSeparator,
        minusSign: format.minusSign,
        zeroDigit: format.zeroDigit,
      );

  /// Nothing to forget: a numeric key is a function of the line it was read from, so the same
  /// number always produces the same keys no matter what came before it.
  @override
  void reset() {}
}
