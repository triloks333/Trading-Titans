import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/animated_premium_banner.dart';

void main() {
  testWidgets('AnimatedPremiumBanner renders title, badge, CTA and responds to tap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedPremiumBanner(
            onTap: () {
              tapped = true;
            },
          ),
        ),
      ),
    );

    // Initial frame
    expect(find.text('START FROM ₹199'), findsOneWidget);
    expect(find.text('Boost Your Capital'), findsOneWidget);
    expect(find.text('Top Up Now'), findsOneWidget);

    // Pump frames to ensure animations progress smoothly without error
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1500));

    // Tap the banner
    await tester.tap(find.byType(AnimatedPremiumBanner));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
