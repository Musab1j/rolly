# The animation model

Every constant in `lib/src/transition_model.dart` is explained here. The transition is tuned to
match SwiftUI's `.contentTransition(.numericText())`, so the numbers are not preferences — moving
one takes the motion further from the thing it is imitating.

## Four channels on two clocks

A glyph changing is four overlapping animations, not one. Each channel is the step response `p(t)`
of a second-order system — see `spring.dart`, which evaluates them in closed form rather than
integrating, so frame rate and dropped frames cannot change the result.

| channel | arriving glyph | departing glyph | ζ | response |
|---|---|---|---|---|
| offset | `dy = 0.59375·(1−p)` | `dy = −0.59375·p` | **0.55** | 353 ms |
| scale | `s = 0.3984 + 0.6016·p` | `s = 1 − 0.6016·p` | 1.00 | 278 ms |
| alpha | `a = p` | `a = 1 − p` | 1.00 | 276 ms |
| blur | `σ = 0.125·(1−p)` | `σ = 0.125·p` | 0.91 | 398 ms |

Offsets and blur sigmas are in glyph heights (font ascent + descent).

Three things this table is saying:

- **Position needs its own spring.** Offset overshoots — it crosses rest ~135 ms after onset,
  reaches −0.072 glyph heights, and returns by ~390 ms. Scale and alpha never overshoot, so one
  spring cannot drive all four.
- **`0.59375` is an entry offset, not a spacing.** A column going `4 → 6` starts exactly as far
  away as one going `4 → 5`. A jump of 8 looks like a jump of 1.
- **The crossfade is convex.** `α_departing + α_arriving ≈ 1` at every instant. It falls out of the
  curves rather than being normalised afterwards — two overlapping blurred glyphs would otherwise
  read darker than one solid one.

## A column holds two glyphs, not a drum

A rolling column is one departing glyph and one arriving glyph crossfading — not a position on a
ten-stop wheel. A column going `4 → 6` while counting down sweeps eight intermediate digits to the
eye, yet every frame is built from just the settled `4` and the settled `6`.

## Direction is global

One vertical direction per transition, decided by whether the **number** grew or shrank — never
per digit.

| | departing | arriving |
|---|---|---|
| counting up | exits downward | enters from above |
| counting down | exits upward | enters from below |

The case that rules out per-digit direction is `0 → −1`: the units digit goes 0 → 1, a numeric
*increase*, and it still rolls in the decrement direction with everything else. Likewise in
`1,242 → 1,160` the tens digit goes 4 → 6 while the number goes down.

## The cascade

Columns start left to right — most significant first — on a **fixed budget**:

```
delay_i = 0.15s · i/(n−1)
```

split among only the columns that actually change, leader at zero. Two changing columns are 150 ms
apart; five are 37.5 ms apart. A long number therefore does not take proportionally longer.

**A structural change does not stagger.** On `9,950 → 10,123` every column starts together, because
the horizontal re-layout is not part of the cascade and staggering against it reads as a stumble.

## Structural changes

When a glyph column is born or dies — `999 → 1,000`, `10,000 → 1,000` — the affected columns use
independent enter/exit lifecycles instead of a roll. A new digit appears **in place**, small and
blurred, and grows; a removed digit shrinks and blurs away in place. Neither shows the large
vertical entry a roll has. In code that is a single change: `entryOffset = 0`.

The classifier keys on **structure, never pixel width** — fonts and separators change a line's
width without changing its structure.

Two layout consequences:

- Surviving glyphs glide between their old and new positions on an early-start, slow ease of
  ~220 ms. It is a slow slide from the first frame, not a delay followed by a slide.
- **Dying glyphs fade where they stand.** Letting them ride the contracting layout slides every
  corpse toward the centre and piles them into an unreadable smear on a big shrink.

## Interruption

A transition is **never cancelled, retargeted or dropped**. When the value changes mid-flight, the
glyph being replaced simply keeps running the same exit law every departing glyph runs. What makes
ordinary cadences look like a clean pair is only that older transitions have faded to near nothing
by the time the next one lands.

| cadence | glyphs meaningfully alive |
|---|---|
| isolated change | 2 |
| ~220 ms tap | 2 (a third at α ≈ 0.1) |
| ~30 ms burst | 3, sometimes 4 |

Under a fast sustained roll a column shows only the real committed values — never an intermediate
digit — and degrades into a soft, dim pair, recovering once the changes stop. That degradation is
designed behaviour, not a defect.

This is why the engine stores no velocity and nothing a frame mutates: an entry is its starting
conditions plus the instant it began. Interruption then costs nothing, because there is no state to
unwind.

One refinement beyond the plain curves: a glyph interrupted before it reached full opacity scales
its exit curves by the alpha, offset, scale and blur it had actually reached, rather than restarting
the exit law from 1.0. For a settled glyph this reduces exactly to the plain form; for an
interrupted one it avoids a visible jump.

## Arbitrary text

The model above says nothing about numbers. Springs, cascade, births and deaths, interruption — all
of it operates on *columns*, and a column is whatever the keying says it is. Extending the
transition to text is therefore one substitution: replace how a glyph is identified, and change
nothing else.

A formatted number can be keyed from a single line, in isolation, because it has structure to key
on: the third integer digit is the third integer digit whatever the previous value was. Text has no
such structure, so identity has to be **found**, by diffing each new line against the one on screen.
That is the whole of `text_slots.dart`, and it is why its keyer is stateful where the numeric one is
not.

The diff is a longest common subsequence over the line's units, read in two passes:

- **A matched unit keeps its key.** It is the same glyph, so it only reflows — `Saving` → `Saved`
  slides the shared letters rather than rebuilding the word.
- **A replaced run is zipped positionally.** Where a stretch of the old line was deleted and a
  stretch of the new line inserted in the same place, the two are paired off from the left and the
  pairs reuse the old keys. The engine then sees one column showing something new, which is a roll.
  Without this, `ON` → `OFF` would dissolve the `N` and pop an `F` in beside it; with it the `N`
  rolls into an `F` and only the second `F` is born. Whichever run is longer spills over into
  ordinary births and deaths.

Two things follow from every unit being laid out on its own — which is what makes a unit movable,
and is not negotiable:

- **A unit has to be something that can stand alone.** `TextSplit.character` splits on grapheme
  clusters, with one exception: a run of joining script stays whole. Arabic is shaped by context —
  `ل` alone is `ل`, but between two letters it is a bare vertical stroke — so cutting between two
  letters renders both in their isolated forms at positions measured for their joined ones. The word
  comes apart, overlaps itself and stops reading as what it says. There is no correct way to animate
  the letters of a cursive word separately while each is typeset alone, so the splitter does not
  try. `TextSplit.word` remains a choice about prose, not a workaround.
- **Base direction is a measurement input.** `LineGeometry` takes a `TextDirection`, because where a
  neutral character lands in a mixed-script line depends on it, and every slot position downstream
  inherits that. Slots are then sorted by screen position, so the cascade runs left to right on
  screen even when the string's logical order does not.

## Where each piece lives

| file | responsibility |
|---|---|
| `spring.dart` | the closed-form step response, all three damping branches |
| `transition_model.dart` | the constants above, and nothing else |
| `numeric_format.dart` | turns a number into a line, and names its separators |
| `slot_keying.dart` | the seam: what identifies a glyph, and nothing about how it moves |
| `keyed_slots.dart` | numeric identity — what counts as "the same glyph" across two values |
| `text_slots.dart` | text identity — the diff, and how a line is cut into units |
| `line_geometry.dart` | typesets the whole line once, reports per-glyph bounds |
| `roll_engine.dart` | columns, entries, onsets, cascade, per-frame sampling |
| `numeric_text_painter.dart` | transform, blur, alpha, edge fade |
| `rolling_line.dart` | one line of glyphs: the engine, the ticker and the caches |
| `numeric_text_widget.dart` | `NumericText` — formats a number, picks a roll direction |
| `rolling_text_widget.dart` | `RollingText` — the same, for a string |
