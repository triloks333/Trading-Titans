// Widget tests for the pure, dependency-free shared widgets in lib/widgets.
//
// These widgets have no network/backend dependencies, so they can be pumped
// directly inside a MaterialApp/Scaffold and verified against their rendered
// output. They lock down the empty/error/stat/trend building blocks used
// across many screens, so a regression in one place is caught here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/widgets/empty_state.dart';
import 'package:mobile/widgets/error_state.dart';
import 'package:mobile/widgets/stat_cell.dart';
import 'package:mobile/widgets/trend_arrow.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyState', () {
    testWidgets('renders icon, title and message', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'No orders yet',
        message: 'Your placed orders will appear here.',
      )));

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Your placed orders will appear here.'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
    });

    testWidgets('hides CTA when no action provided', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Empty',
        message: 'Nothing here.',
      )));

      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('shows CTA and fires onAction when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.search_rounded,
        title: 'Start trading',
        message: 'Place your first trade.',
        actionLabel: 'Explore stocks',
        onAction: () => tapped = true,
      )));

      expect(find.text('Explore stocks'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('ErrorState', () {
    testWidgets('shows default copy and the "Couldn\'t load" headline',
        (tester) async {
      await tester.pumpWidget(_wrap(const ErrorState()));

      expect(find.text("Couldn't load"), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('renders custom message', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorState(
        message: 'Network is down.',
      )));

      expect(find.text('Network is down.'), findsOneWidget);
    });

    testWidgets('hides Retry when no onRetry given', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorState()));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows Retry and fires onRetry when tapped', (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(ErrorState(
        onRetry: () => retried = true,
      )));

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });

  group('StatCell', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_wrap(const Row(
        children: [
          StatCell(label: 'Invested', value: '₹1,000.00'),
        ],
      )));

      expect(find.text('Invested'), findsOneWidget);
      expect(find.text('₹1,000.00'), findsOneWidget);
    });

    testWidgets('does not wrap in Expanded when expanded is false',
        (tester) async {
      await tester.pumpWidget(_wrap(const StatCell(
        label: 'P&L',
        value: '+₹500.00',
        expanded: false,
      )));

      expect(find.byType(Expanded), findsNothing);
      expect(find.text('P&L'), findsOneWidget);
    });
  });

  group('TrendArrow', () {
    testWidgets('shows an up caret when positive', (tester) async {
      await tester.pumpWidget(_wrap(const TrendArrow(isPositive: true)));
      expect(find.byIcon(Icons.arrow_drop_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsNothing);
    });

    testWidgets('shows a down caret when negative', (tester) async {
      await tester.pumpWidget(_wrap(const TrendArrow(isPositive: false)));
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_up_rounded), findsNothing);
    });
  });
}
