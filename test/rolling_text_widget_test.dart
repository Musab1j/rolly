import 'package:rolly/rolly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Wraps [child] so it has the ambient text style, direction and media query a real app
  /// provides.
  Widget host(
    Widget child, {
    bool disableAnimations = false,
    TextDirection textDirection = TextDirection.ltr,
  }) => MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: textDirection,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 32, color: Color(0xFF000000)),
        child: Center(child: child),
      ),
    ),
  );

  testWidgets('lays out at the size of the text it is showing', (tester) async {
    await tester.pumpWidget(host(const RollingText('Connected')));

    final size = tester.getSize(find.byType(RollingText));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
  });

  testWidgets('animates to new text and settles', (tester) async {
    await tester.pumpWidget(host(const RollingText('Connecting')));
    await tester.pumpWidget(host(const RollingText('Connected')));

    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('identical text does not start a transition', (tester) async {
    await tester.pumpWidget(host(const RollingText('Idle')));
    await tester.pumpWidget(host(const RollingText('Idle')));
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'snaps instead of animating when the platform asks for reduced motion',
    (tester) async {
      await tester.pumpWidget(
        host(const RollingText('Idle'), disableAnimations: true),
      );
      await tester.pumpWidget(
        host(const RollingText('Running'), disableAnimations: true),
      );
      await tester.pump();

      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'grows the box for the transition, then collapses to the settled width',
    (tester) async {
      await tester.pumpWidget(host(const RollingText('Downloading updates')));
      final wide = tester.getSize(find.byType(RollingText)).width;

      await tester.pumpWidget(host(const RollingText('Done')));
      await tester.pump(const Duration(milliseconds: 30));
      final during = tester.getSize(find.byType(RollingText)).width;

      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final settled = tester.getSize(find.byType(RollingText)).width;

      expect(during, closeTo(wide, 0.01));
      expect(settled, lessThan(wide));
    },
  );

  testWidgets('survives rapid retargeting', (tester) async {
    const phrases = [
      'Idle',
      'Connecting…',
      'Connected',
      'Syncing 1 of 12',
      'Done',
      '',
    ];

    await tester.pumpWidget(host(const RollingText('Idle')));
    for (var i = 0; i < 40; i++) {
      await tester.pumpWidget(host(RollingText(phrases[i % phrases.length])));
      await tester.pump(const Duration(milliseconds: 30));
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the split mid-flight does not throw', (tester) async {
    Widget build(String text, TextSplit split) =>
        host(RollingText(text, split: split));

    await tester.pumpWidget(build('now loading', TextSplit.character));
    await tester.pumpWidget(build('now done', TextSplit.character));
    await tester.pump(const Duration(milliseconds: 40));

    // The keyer's history describes columns that no longer exist at this granularity, so the
    // line has to restart rather than diff against it.
    await tester.pumpWidget(build('now done', TextSplit.word));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a right-to-left line lays out and transitions', (tester) async {
    Widget build(String text) => host(
      RollingText(text, split: TextSplit.word),
      textDirection: TextDirection.rtl,
    );

    await tester.pumpWidget(build('جاري التحميل'));
    expect(tester.getSize(find.byType(RollingText)).width, greaterThan(0));

    await tester.pumpWidget(build('تم التحميل'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a screen reader hears the text it is showing', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(host(const RollingText('Connecting')));
    expect(find.bySemanticsLabel('Connecting'), findsOneWidget);

    await tester.pumpWidget(host(const RollingText('Connected')));
    expect(find.bySemanticsLabel('Connected'), findsOneWidget);
    expect(find.bySemanticsLabel('Connecting'), findsNothing);

    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    semantics.dispose();
  });
}
