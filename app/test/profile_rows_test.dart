// Every row on the rebuilt Profile screen opens the screen it names.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/analytics_screen.dart';
import 'package:mobile/screens/main/autopsy_screen.dart';
import 'package:mobile/screens/main/challenges_screen.dart';
import 'package:mobile/screens/main/chat_screen.dart';
import 'package:mobile/screens/main/glossary_screen.dart';
import 'package:mobile/screens/main/notifications_screen.dart';
import 'package:mobile/screens/main/orders_screen.dart';
import 'package:mobile/screens/main/profile_screen.dart';
import 'package:mobile/screens/main/refer_earn_screen.dart';
import 'package:mobile/screens/main/watchlist_screen.dart';
import 'package:mobile/screens/main/whatif_screen.dart';
import 'package:mobile/services/app_flags_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/services/plan_service.dart';
import 'package:mobile/services/theme_service.dart';

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

const rows = <String, Type>{
  'Challenges & rewards': ChallengesScreen,
  'Refer & earn': ReferEarnScreen,
  'Order history': OrdersScreen,
  'Watchlists': WatchlistScreen,
  'Analytics': AnalyticsScreen,
  'Trade autopsy': AutopsyScreen,
  'What-If simulator': WhatIfScreen,
  'Trading glossary': GlossaryScreen,
  'Titans Room': ChatScreen,
  'Notifications': NotificationsScreen,
};

/// Scrolls [f] fully into view, so a tap lands on it rather than off-screen.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'profile-rows-test-key');
  });

  Future<void> pumpProfile(WidgetTester tester) async {
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
      child: MaterialApp(theme: AppTheme.darkTheme, home: const ProfileScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final e in rows.entries) {
    testWidgets('"${e.key}" opens ${e.value}', (tester) async {
      await pumpProfile(tester);
      final row = find.text(e.key);
      await _reveal(tester, row);
      await tester.tap(row);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(e.value), findsOneWidget);
    });
  }

  testWidgets('"Settings" opens the settings page', (tester) async {
    await pumpProfile(tester);
    final row = find.text('Settings');
    await _reveal(tester, row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('APPEARANCE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delete account'), 150, scrollable: find.byType(Scrollable).last);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('Sign out row is present and the footer names the operator', (tester) async {
    await pumpProfile(tester);
    final out = find.text('Sign out');
    await _reveal(tester, out);
    expect(out, findsOneWidget);
    final footer = find.textContaining('Kashivwealth Management LLP');
    await _reveal(tester, footer);
    expect(footer, findsOneWidget);
  });
}
