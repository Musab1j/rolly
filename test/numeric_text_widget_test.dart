import 'package:rolly/rolly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Wraps [child] so it has the ambient text style and media query a real app provides.
  Widget host(
    Widget child, {
    bool disableAnimations = false,
    TextAlign ambientAlign = TextAlign.start,
  }) => MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 48, color: Color(0xFF000000)),
        // Not read by NumericText, but changing it makes DefaultTextStyle notify its dependents
        // without altering the resolved style - which is exactly the situation the widget has to
        // tell apart from a real restyle.
        textAlign: ambientAlign,
        child: Center(child: child),
      ),
    ),
  );

  testWidgets('lays out at the size of the number it is showing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(NumericText(value: 1234, format: const NumericTextFormat.integer())),
    );

    final size = tester.getSize(find.byType(NumericText));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });

  testWidgets('animates to a new value and settles', (tester) async {
    Widget build(num value) => host(
      NumericText(value: value, format: const NumericTextFormat.integer()),
    );

    await tester.pumpWidget(build(999));
    await tester.pumpWidget(build(1000));

    // Mid-transition the ticker is running, so frames keep being scheduled.
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // ...and it stops on its own rather than spinning forever.
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'grows the box for the transition, then collapses to the settled width',
    (tester) async {
      Widget build(num value) => host(
        NumericText(value: value, format: const NumericTextFormat.integer()),
      );

      await tester.pumpWidget(build(1000));
      final wide = tester.getSize(find.byType(NumericText)).width;

      await tester.pumpWidget(build(1));
      await tester.pump(const Duration(milliseconds: 30));
      final during = tester.getSize(find.byType(NumericText)).width;

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final settled = tester.getSize(find.byType(NumericText)).width;

      // While glyphs are still leaving, the box keeps the old line's room so nothing is cut off.
      expect(during, closeTo(wide, 0.01));
      // Once they are gone it takes only the space the number needs.
      expect(settled, lessThan(wide));
    },
  );

  testWidgets(
    'snaps instead of animating when the platform asks for reduced motion',
    (tester) async {
      Widget build(num value) => host(
        NumericText(value: value, format: const NumericTextFormat.integer()),
        disableAnimations: true,
      );

      await tester.pumpWidget(build(1));
      await tester.pumpWidget(build(9999));
      await tester.pump();

      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('a value that formats identically does not start a transition', (
    tester,
  ) async {
    const twoPlaces = NumericTextFormat.decimal(
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    );
    Widget build(num value) =>
        host(NumericText(value: value, format: twoPlaces));

    await tester.pumpWidget(build(1.0));
    await tester.pumpWidget(build(1.004)); // still "1.00"
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('survives rapid retargeting', (tester) async {
    Widget build(num value) => host(
      NumericText(value: value, format: const NumericTextFormat.integer()),
    );

    await tester.pumpWidget(build(0));
    for (var i = 1; i <= 40; i++) {
      await tester.pumpWidget(build(i * 137));
      await tester.pump(const Duration(milliseconds: 30));
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('restyling mid-flight does not throw', (tester) async {
    Widget build(num value, double size) => host(
      NumericText(
        value: value,
        format: const NumericTextFormat.integer(),
        style: TextStyle(fontSize: size),
      ),
    );

    await tester.pumpWidget(build(999, 48));
    await tester.pumpWidget(build(1000, 48));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(build(1000, 72));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrelated dependency change does not abandon a transition', (
    tester,
  ) async {
    Widget build(num value, TextAlign ambient) => host(
      NumericText(value: value, format: const NumericTextFormat.integer()),
      ambientAlign: ambient,
    );

    await tester.pumpWidget(build(999, TextAlign.start));
    await tester.pumpWidget(build(1000, TextAlign.start));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Something inherited changed, but nothing this widget actually renders from. Snapping here
    // would kill the transition halfway and read as the number glitching.
    await tester.pumpWidget(build(1000, TextAlign.end));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'the transition should still be running',
    );

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('every transition runs as promptly as the first', (tester) async {
    Widget build(num value) => host(
      NumericText(value: value, format: const NumericTextFormat.integer()),
    );

    await tester.pumpWidget(build(100));

    final frames = <int>[];
    for (final value in [101, 102, 103]) {
      await tester.pumpWidget(build(value));
      frames.add(await tester.pumpAndSettle(const Duration(milliseconds: 16)));
    }

    // Each of these is the same transition, so each should cost about the same number of frames.
    // A transition that takes steadily longer means the engine is being sampled at a time that
    // has drifted away from the onsets it was given - the number sits frozen until the clock
    // catches up.
    expect(frames[1], lessThan(frames[0] * 3 ~/ 2), reason: 'frames: $frames');
    expect(frames[2], lessThan(frames[0] * 3 ~/ 2), reason: 'frames: $frames');
  });

  testWidgets(
    'a screen reader hears the formatted value, never a frame of the animation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      Widget build(num value) => host(
        NumericText(value: value, format: const NumericTextFormat.integer()),
      );

      await tester.pumpWidget(build(1234));
      expect(find.bySemanticsLabel('1,234'), findsOneWidget);

      // Mid-flight the glyphs on screen are neither value, but the label is already the new one.
      await tester.pumpWidget(build(99));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.bySemanticsLabel('99'), findsOneWidget);
      expect(find.bySemanticsLabel('1,234'), findsNothing);

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      semantics.dispose();
    },
  );
}
