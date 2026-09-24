<h1 align="center">rolly</h1>

<p align="center">
  Numbers and text that animate the way they do on iOS.<br>
  Digits roll, the line reflows, glyphs are born and die in place.
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Musab1j/rolly/main/doc/rolly.gif" width="640" alt="A currency value rolling between amounts while a caption below it morphs from one phrase to the next">
</p>

<p align="center">
  <a href="https://pub.dev/packages/rolly"><img src="https://img.shields.io/pub/v/rolly.svg" alt="pub package"></a>
  <img src="https://img.shields.io/badge/dependencies-Flutter%20SDK%20only-brightgreen.svg" alt="no dependencies beyond the Flutter SDK">
</p>

---

## Install

```yaml
dependencies:
  rolly: ^0.1.0
```

## Use

A number that animates whenever it changes:

```dart
NumericText(
  value: total,
  format: const NumericTextFormat.currency(),
  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w700),
)
```

The same transition over any string:

```dart
RollingText(
  status,                                 // 'Connecting…' -> 'Connected'
  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
)
```

Both behave like `Text` in layout, take the ambient `DefaultTextStyle`, and honour the platform's
reduced-motion setting. Nothing else is required — no controller, no ticker, no builder.

## Formats

```dart
const NumericTextFormat.integer()                         // 1,234
const NumericTextFormat.decimal(maximumFractionDigits: 2) // 1,234.5
const NumericTextFormat.currency(symbol: r'$')            // $1,234.50
const NumericTextFormat.percent()                         // 12.5%
```

Separators are arguments, not locale lookups, so any convention works:

```dart
const NumericTextFormat.decimal(
  groupSeparator: '.',
  decimalSeparator: ',',
  minimumFractionDigits: 2,
)                                                         // 1.234,50
```

And for real locale data — per-country currency symbols, compact notation, anything else —
`NumericTextFormat.custom` takes a formatting function, `intl`'s included:

```dart
final de = NumberFormat.currency(locale: 'de_DE');

NumericTextFormat.custom(
  de.format,
  groupSeparator: de.symbols.GROUP_SEP,
  decimalSeparator: de.symbols.DECIMAL_SEP,
  minusSign: de.symbols.MINUS_SIGN,
);
```

That is the reason this package depends on nothing beyond what Flutter itself ships (its one
dependency, `characters`, is already pinned by the Flutter SDK): `intl` is yours to add if you want
it, not a version constraint you inherit.

## Options

Both widgets take:

| | |
|---|---|
| `style` | merged over `DefaultTextStyle`, as `Text` does |
| `duration` | 320 ms by default; other values stretch every channel by the same factor |
| `direction` | `automatic` reads it from the change itself, or force `up` / `down` |
| `reduceMotion` | `system`, `always` (snap), or `never` |
| `textAlign` | which edge the line is pinned to while its width changes |
| `edgeFade` | softens the top and bottom of the rolling area |

`NumericText` adds `value`, `format` and `fractionColor` — a second colour for the decimal mark
and everything after it, for de-emphasising cents. `RollingText` adds `split`, which animates the
line by character or by word.

## How it works

- **Four channels, two springs.** A glyph moves, grows, fades and comes into focus at once, on
  different clocks. Position gets a bouncy spring that overshoots; scale and alpha share a
  critically damped one; blur is slowest of all, which is most of what separates this from a hard
  digit flip.
- **A column holds two glyphs, not a drum.** `4 → 6` crossfades a settled 4 with a settled 6.
  Nothing spins through 5.
- **Births and deaths are not rolls.** When `999` becomes `1,000` the new digit appears in place,
  small and blurred, and grows. Surviving glyphs slide to their new positions; dying ones fade
  where they stand rather than riding the layout inward.
- **The cascade is a fixed budget.** Columns start left to right across 150 ms total, however many
  of them change, so a long number does not take proportionally longer.
- **Interruption is free.** A transition is never cancelled or retargeted. A glyph stores its
  starting conditions and the instant it began, so a value changing mid-flight costs nothing to
  absorb — hold the stepper down and columns degrade into a soft pair, then recover.

Text works the same way: the model operates on columns, and a column is whatever identifies a
glyph. Numbers are keyed from their own structure; a string is diffed against the one on screen, so
matched characters reflow, replaced ones roll, and the rest are born or die.

`doc/animation_model.md` has the full model, constant by constant.

## Example

`example/` is a playground covering every feature: each format, a stepper that accelerates while
held, a scripted stress run, the text transition, and live controls for duration, size, direction,
reduced motion and edge fade.

```bash
cd example && flutter run
```

## Built with AI

This package — the implementation, its tests, the documentation and the example app — was
generated with AI assistance (Claude), then reviewed and tested before release. The test suite is
the honest description of what is verified: 100 tests covering the curves, the keying, the engine's
behaviour under interruption, and full-sequence integrity checks.

## Credits

The transition is modelled on SwiftUI's `.contentTransition(.numericText())`. The animation
constants were derived from the open-source measurements published by
[react-native-numeric-text](https://github.com/AmatoGiulio/react-native-numeric-text), which
decomposed the original transition frame by frame.
