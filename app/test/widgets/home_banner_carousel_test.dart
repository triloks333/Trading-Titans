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

    // Fling to Slide 2
    await tester.fling(find.byType(PageView), const Offset(-800, 0), 1000);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Slide 2 (Titan Pro Mentorship)
    expect(find.text('Titan Pro Membership'), findsOneWidget);
    expect(find.text('FOUNDER MENTORSHIP · ₹1L+/MO VALUE'), findsOneWidget);
    expect(find.text('Join for ₹999'), findsOneWidget);

    // Fling to Slide 3
    await tester.fling(find.byType(PageView), const Offset(-800, 0), 1000);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Slide 3 (Glossary Hub)
    expect(find.text('Master Trading Terms'), findsOneWidget);
    expect(find.text('KNOWLEDGE HUB · ZERO RISK'), findsOneWidget);
    expect(find.text('Explore Glossary'), findsOneWidget);

    // Tap Slide 3
    await tester.tap(find.text('Explore Glossary'));
    await tester.pump();
    expect(glossaryTapped, isTrue);
  });
}
