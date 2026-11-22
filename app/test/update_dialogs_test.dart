import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/widgets/update_dialogs.dart';

const _notes = '• New: Commodities! Trade gold and silver\n'
    '- Buy by amount\n'
    '\n'
    '* Charts follow dark mode';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('soft update dialog shows version, clean notes and the update button', (tester) async {
    await pump(
      tester,
      SoftUpdateDialog(updateUrl: 'https://example.com', releaseNotes: _notes, version: '2.0.5', onDismiss: () {}),
    );

    expect(find.text('VERSION 2.0.5'), findsOneWidget);
    expect(find.text("WHAT'S NEW"), findsOneWidget);
    // Leading bullet glyphs are stripped and blank lines dropped.
    expect(find.text('New: Commodities! Trade gold and silver'), findsOneWidget);
    expect(find.text('Buy by amount'), findsOneWidget);
    expect(find.text('Charts follow dark mode'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
    expect(find.text('Update now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('soft update dialog hides the pill and notes when config has none', (tester) async {
    await pump(tester, SoftUpdateDialog(updateUrl: 'x', releaseNotes: '', onDismiss: () {}));

    expect(find.textContaining('VERSION'), findsNothing);
    expect(find.text("WHAT'S NEW"), findsNothing);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('hard update gate renders and cannot be popped', (tester) async {
    await pump(tester, const HardUpdateGate(updateUrl: 'x', releaseNotes: _notes, version: '2.0.5'));

    expect(find.text('Time to update'), findsOneWidget);
    expect(find.text('VERSION 2.0.5'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    final scope = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(scope.canPop, isFalse);
    expect(tester.takeException(), isNull);
  });
}
