// Lightweight widget + formatting smoke tests.
//
// The original default-scaffold "counter" test was removed: it pumped the full
// backend-dependent app (Supabase/Firebase) and checked a counter widget that
// never existed, so it always failed. These tests verify the widget harness
// works and lock down the INR currency formatter used across the app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme.dart';

void main() {
  group('AppFormat.formatINR', () {
    test('prefixes rupee symbol with two decimals', () {
      expect(AppFormat.formatINR(1234.5), '₹1234.50');
      expect(AppFormat.formatINR(0), '₹0.00');
    });

    test('handles negative values', () {
      expect(AppFormat.formatINR(-12.3), '₹-12.30');
    });
  });

  testWidgets('widget test harness renders a basic frame', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Trading Titans'))),
    );
    expect(find.text('Trading Titans'), findsOneWidget);
  });
}
