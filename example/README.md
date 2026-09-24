# rolly playground

Every part of the transition on one screen: each number format, a stepper that accelerates while
held, a scripted stress run, the text transition split by character or by word, and live controls
for duration, size, direction, reduced motion and edge fade.

```bash
flutter run
```

The interesting things to try:

- **Hold the `+` button.** It fires faster and faster. Columns degrade into a soft pair under a
  burst and recover once you let go — they never show a digit that was not a real value.
- **Press *Random jump*.** A surviving column enters from the same fixed distance however far the
  number moved, so a jump from 7 to 4,918,204 reads through columns being born, not through digits
  spinning further.
- **Switch format while a number is on screen.** The value jumps too, so every switch is a
  structural change.
- **Play the stress run.** Structural changes both ways, a sign crossing, a 60 ms burst, and a
  reversal mid-flight.
