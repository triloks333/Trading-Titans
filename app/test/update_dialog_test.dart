// The in-app update prompt (SoftUpdateDialog) and the hard gate share one look.
// Pinned here: release notes parse the same with or without bullet glyphs, the
// version chip shows what is known, the prompt cannot be dismissed, and a store
// that fails to open keeps the prompt up with an error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/widgets/update_dialogs.dart';

const _notes = '''
• New: Commodities! Trade gold, silver, crude oil
• Buy commodities by amount, so you can start small

- Charts now follow light and dark mode
''';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('parseReleaseNotes', () {
    test('drops blank lines and leading bullets of any style', () {
      expect(parseReleaseNotes(_notes), [
        'New: Commodities! Trade gold, silver, crude oil',
        'Buy commodities by amount, so you can start small',
        'Charts now follow light and dark mode',
      ]);
    });

    test('empty notes give no lines', () {
      expect(parseReleaseNotes(''), isEmpty);
      expect(parseReleaseNotes('  \n \n'), isEmpty);
    });
  });

  group('SoftUpdateDialog', () {
    Future<void> open(WidgetTester tester, {String current = '2.0.4', String url = 'not a url'}) async {
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => SoftUpdateDialog(
              updateUrl: url,
              releaseNotes: _notes,
              latestVersion: '2.0.5',
              currentVersion: current,
              onDismiss: () {},
            ),
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows both versions, tagged notes and the button', (tester) async {
      await open(tester);
      expect(find.text('v2.0.4'), findsOneWidget);
      expect(find.text('v2.0.5'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget); // "New:" lifted into a tag
      expect(find.textContaining('Buy commodities by amount', findRichText: true), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
    });

    testWidgets('chip shows only the target when the installed version is unknown', (tester) async {
      await open(tester, current: '');
      expect(find.text('v2.0.5'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    });

    testWidgets('back does not dismiss it', (tester) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SoftUpdateDialog), findsOneWidget);
    });

    testWidgets('a store that cannot open keeps the prompt and says so', (tester) async {
      await open(tester, url: '');
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(find.byType(SoftUpdateDialog), findsOneWidget);
      expect(find.text('Couldn\'t open the store. Please try again.'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget); // spinner cleared
    });
  });

  testWidgets('HardUpdateGate renders without overflow on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: HardUpdateGate(
        updateUrl: 'x',
        releaseNotes: _notes,
        latestVersion: '2.0.5',
        currentVersion: '1.2.10',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Update to keep trading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
