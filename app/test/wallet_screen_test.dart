// Wallet: balance card, earn cards and order history.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/challenges_screen.dart';
import 'package:mobile/screens/main/orders_screen.dart';
import 'package:mobile/screens/main/refer_earn_screen.dart';
import 'package:mobile/screens/main/wallet_screen.dart';
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

Future<void> _pump(WidgetTester tester) async {
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
    child: MaterialApp(theme: AppTheme.darkTheme, home: const WalletScreen()),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _open(WidgetTester tester, String text, Type screen) async {
  final f = find.text(text);
  await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
  await tester.tap(f);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(find.byType(screen), findsOneWidget, reason: text);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'wallet-test-key');
  });

  testWidgets('balance card with invested, blocked and starting cash', (tester) async {
    await _pump(tester);
    for (final t in ['DEMO CASH BALANCE', 'Virtual money for practice. Not withdrawable.', 'Invested', 'Blocked', 'Starting',
      'EARN MORE DEMO CASH', 'TRANSACTION HISTORY']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('per signup'), findsOneWidget);
  });

  testWidgets('Order history opens Orders', (tester) async {
    await _pump(tester);
    await _open(tester, 'Order history', OrdersScreen);
  });
  testWidgets('Challenges card opens Challenges', (tester) async {
    await _pump(tester);
    await _open(tester, 'Challenges', ChallengesScreen);
  });
  testWidgets('Refer card opens Refer & earn', (tester) async {
    await _pump(tester);
    await _open(tester, 'Refer a friend', ReferEarnScreen);
  });
}
