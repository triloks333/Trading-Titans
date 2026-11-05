// Profile & settings pages: Settings, Preferences, Legal, Glossary, Delete
// account, Make permanent and the Admin panel.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/glossary.dart';
import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/admin_panel_screen.dart';
import 'package:mobile/screens/main/convert_account_screen.dart';
import 'package:mobile/screens/main/glossary_quiz_screen.dart';
import 'package:mobile/screens/main/glossary_screen.dart';
import 'package:mobile/screens/main/settings_screen.dart';
import 'package:mobile/services/app_flags_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/services/plan_service.dart';
import 'package:mobile/services/theme_service.dart';
import 'package:mobile/widgets/legal_sheet.dart';

Future<void> _loadFonts() async {
  final sans = File('C:/Windows/Fonts/arial.ttf'), mono = File('C:/Windows/Fonts/consola.ttf');
  if (!sans.existsSync() || !mono.existsSync()) return;
  final variants = ['regular', 'italic', for (final w in [100, 200, 300, 500, 600, 700, 800, 900]) ...['$w', '${w}italic']];
  for (final (family, file) in [('IBMPlexSans', sans), ('IBMPlexMono', mono)]) {
    for (final v in variants) {
      await (FontLoader('${family}_$v')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())))).load();
    }
  }
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthService()),
      ChangeNotifierProvider.value(value: ThemeService()),
      ChangeNotifierProvider.value(value: AppFlagsService.instance),
      ChangeNotifierProvider.value(value: CurrencyService.instance),
      ChangeNotifierProvider.value(value: PlanService.instance),
    ],
    child: MaterialApp(theme: AppTheme.darkTheme, home: home),
  ));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapRow(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'settings-test-key');
  });

  group('Settings', () {
    testWidgets('sections and footer', (tester) async {
      await _pump(tester, const SettingsScreen());
      for (final c in ['APPEARANCE', 'TRADING', 'NOTIFICATIONS']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      expect(find.text('App theme'), findsOneWidget);
      final footer = find.textContaining('Kashivwealth Management LLP');
      await tester.scrollUntilVisible(footer, 150, scrollable: find.byType(Scrollable).first);
      expect(footer, findsOneWidget);
      expect(find.text('HELP & ABOUT'), findsOneWidget);
    });

    testWidgets('rows open Preferences, Glossary and both Legal tabs', (tester) async {
      await _pump(tester, const SettingsScreen());
      await _tapRow(tester, 'Preferred markets');
      expect(find.byType(PreferencesScreen), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back').last);
      await _settle(tester);

      await _tapRow(tester, 'Trading glossary');
      expect(find.byType(GlossaryScreen), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back').last);
      await _settle(tester);

      await _tapRow(tester, 'Privacy policy');
      expect(find.byType(LegalScreen), findsOneWidget);
      expect(tester.widget<LegalScreen>(find.byType(LegalScreen)).privacy, isTrue);
    });

    testWidgets('Delete account needs DELETE typed before it enables', (tester) async {
      await _pump(tester, const SettingsScreen());
      await _tapRow(tester, 'Delete account');
      expect(find.text('Delete account?'), findsOneWidget);
      ElevatedButton delete() => tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Delete permanently'));
      expect(delete().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pump();
      expect(delete().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(delete().onPressed, isNotNull, reason: 'case-insensitive DELETE');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(find.text('Delete account?'), findsNothing);
    });
  });

  testWidgets('Preferences: at most 3 markets, never zero', (tester) async {
    await _pump(tester, const PreferencesScreen());
    final start = CurrencyService.instance.preferredMarkets.length;
    expect(find.text('$start/3'), findsOneWidget);
    for (final (_, label) in kPreferenceMarkets) {
      final f = find.text(label);
      await tester.scrollUntilVisible(f, 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(f);
      await tester.pump();
    }
    // Tapping every market toggles some off and others on, but the count stays 1-3.
    final shown = RegExp(r'^(\d)/3$');
    final count = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').where(shown.hasMatch).map((t) => int.parse(t[0])).first;
    expect(count, inInclusiveRange(1, 3));
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Legal: tabs switch documents', (tester) async {
    await _pump(tester, const LegalScreen());
    expect(find.text('Legal'), findsOneWidget);
    expect(find.textContaining('Kashivwealth Management LLP'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Privacy policy'));
    await tester.pump();
    expect(find.textContaining('1. '), findsWidgets);
  });

  testWidgets('Glossary: search, category and expand', (tester) async {
    await _pump(tester, const GlossaryScreen());
    final first = Glossary.terms.first;
    expect(filterGlossary(first.term, 'All').map((t) => t.term), contains(first.term));
    expect(filterGlossary('zzzz-nothing', 'All'), isEmpty);
    await tester.enterText(find.byType(TextField), first.term);
    await tester.pump();
    await tester.tap(find.text(first.term).last);
    await tester.pump();
    expect(find.text(first.definition), findsOneWidget);
    await tester.tap(find.text('Test yourself · glossary quiz'));
    await _settle(tester);
    expect(find.byType(GlossaryQuizScreen), findsOneWidget);
  });

  testWidgets('Make permanent: a non-guest sees it is already permanent', (tester) async {
    await _pump(tester, const ConvertAccountScreen());
    expect(find.text('Already permanent'), findsOneWidget);
  });

  testWidgets('Admin panel: four tabs', (tester) async {
    await _pump(tester, const AdminPanelScreen());
    for (final t in ['Broadcast', 'Rewards', 'Blog', 'Users']) {
      expect(find.bySemanticsLabel(t), findsOneWidget, reason: t);
    }
    expect(find.text('ADMIN ONLY'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Users'));
    await _settle(tester);
    expect(find.text('Wishlist moderation'), findsOneWidget);
  });
}
