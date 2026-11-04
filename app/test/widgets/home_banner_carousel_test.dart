import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/home_banner_carousel.dart';

void main() {
  testWidgets('HomeBannerCarousel renders initial slide and page dots', (tester) async {
    var subscribeTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeBannerCarousel(
            onSubscribeTap: () => subscribeTapped = true,
          ),
        ),
      ),
    );

    // Initial frame renders Slide 1 (Capital Boost)
    expect(find.text('START FROM ₹199'), findsOneWidget);
    expect(find.text('Boost Your Capital'), findsOneWidget);
    expect(find.text('Top Up Now'), findsOneWidget);

    // Tap Slide 1
    await tester.tap(find.text('Top Up Now'));
    await tester.pump();
    expect(subscribeTapped, isTrue);
  });

  testWidgets('HomeBannerCarousel allows swiping between slides', (tester) async {
    var glossaryTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeBannerCarousel(
            onGlossaryTap: () => glossaryTapped = true,
          ),
        ),
      ),
    );

    // Initial frame: Slide 1 is visible
    expect(find.text('Boost Your Capital'), findsOneWidget);

    // Swipe to Slide 2. Pumped frame by frame until the page snap ends: a
    // PageView still settling swallows taps, and with 4 slides it no longer
    // stops dead against the last page.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify Slide 2 (Titan Pro Mentorship)
    expect(find.text('Titan Pro Membership'), findsOneWidget);
    expect(find.text('FOUNDER MENTORSHIP · ₹1L+/MO VALUE'), findsOneWidget);
    expect(find.text('Join for ₹999'), findsOneWidget);

    // Swipe to Slide 3
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify Slide 3 (Glossary Hub)
    expect(find.text('Master Trading Terms'), findsOneWidget);
    expect(find.text('KNOWLEDGE HUB · ZERO RISK'), findsOneWidget);
    expect(find.text('Explore Glossary'), findsOneWidget);

    // Tap Slide 3
    await tester.tap(find.text('Explore Glossary'));
    await tester.pump();
    expect(glossaryTapped, isTrue);

    // Slide 4: feedback, moved up from Settings
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Request a feature'), findsOneWidget);
    expect(find.text('Report an issue'), findsOneWidget);

    // It opens the same report sheet as Settings.
    await tester.tap(find.text('Report an issue'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Report an Issue'), findsOneWidget);
  });
}
