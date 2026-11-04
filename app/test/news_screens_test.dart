import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/news_list_screen.dart';
import 'package:mobile/screens/main/news_reader_screen.dart';

Future<void> _loadFonts() async {
  final sans = File('C:/Windows/Fonts/arial.ttf'), mono = File('C:/Windows/Fonts/consola.ttf');
  if (!sans.existsSync() || !mono.existsSync()) return;
  final variants = ['regular', 'italic', for (final w in [100, 200, 300, 500, 600, 700, 800, 900]) ...['$w', '${w}italic']];
  for (final (family, file) in [('IBMPlexSans', sans), ('IBMPlexSerif', sans), ('IBMPlexMono', mono)]) {
    for (final v in variants) {
      await (FontLoader('${family}_$v')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
    }
  }
}

Map<String, dynamic> post(String title, String market, {int hoursAgo = 1, String body = 'One.\n\nTwo.\n\nThree.\n\nFour.'}) => {
      'title': title,
      'slug': title.toLowerCase().replaceAll(' ', '-'),
      'excerpt': '[market:$market] Summary of $title',
      'body_markdown': body,
      'cover_url': null,
      'published_at': DateTime.now().toUtc().subtract(Duration(hours: hoursAgo)).toIso8601String(),
    };

Future<void> pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: home));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'news-test-key');
  });

  test('age and read-time labels', () {
    final now = DateTime.utc(2026, 11, 4, 12);
    String age(Duration d) => newsAge(now.subtract(d).toIso8601String(), now: now);
    expect(age(const Duration(minutes: 30)), '30M AGO');
    expect(age(const Duration(hours: 5)), '5H AGO');
    expect(age(const Duration(hours: 30)), 'YESTERDAY');
    expect(age(const Duration(days: 3)), '3D AGO');
    expect(newsReadMinutes(List.filled(800, 'word').join(' ')), 4);
    expect(newsReadMinutes(''), 1);
  });

  testWidgets('list: chips for markets present, filtering, lead story first', (tester) async {
    await pump(tester, NewsListScreen(posts: [
      post('Nifty closes higher', 'stock'),
      post('Bitcoin breaks out', 'crypto', hoursAgo: 3),
      post('Fed holds rates', 'us_stock', hoursAgo: 30),
    ]));
    for (final c in ['All', 'India', 'US', 'Crypto']) {
      expect(find.widgetWithText(ChoiceChip, c), findsOneWidget, reason: c);
    }
    expect(find.widgetWithText(ChoiceChip, 'Italy'), findsNothing, reason: 'no Italy posts');
    expect(find.text('Nifty closes higher'), findsOneWidget);
    expect(find.text('3 MIN READ'), findsNothing);
    expect(find.text('1 MIN READ'), findsOneWidget, reason: 'lead story shows read time');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Crypto'));
    await tester.pump();
    expect(find.text('Bitcoin breaks out'), findsOneWidget);
    expect(find.text('Nifty closes higher'), findsNothing);
  });

  testWidgets('tapping a story opens the reader; continue reveals the rest', (tester) async {
    await pump(tester, NewsListScreen(posts: [post('Nifty closes higher', 'stock')]));
    await tester.tap(find.text('Nifty closes higher'));
    await tester.pumpAndSettle();
    expect(find.byType(NewsReaderScreen), findsOneWidget);
    expect(find.text('Three.'), findsNothing, reason: 'collapsed shows the first half');
    final more = find.text('Read the full story here');
    await tester.scrollUntilVisible(more, 150, scrollable: find.byType(Scrollable).last);
    await tester.tap(more);
    await tester.pump();
    expect(find.text('Three.'), findsOneWidget);
    expect(find.text('You have read the full story.'), findsOneWidget);
    expect(find.text('Trade Indian stocks with demo cash'), findsOneWidget);
  });

  testWidgets('share opens WhatsApp / copy link / website choices', (tester) async {
    await pump(tester, NewsReaderScreen(post: post('Fed holds rates', 'us_stock')));
    await tester.tap(find.bySemanticsLabel('Share article'));
    await tester.pumpAndSettle();
    expect(find.text('Share on WhatsApp'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Open on website'), findsWidgets);
  });
}
