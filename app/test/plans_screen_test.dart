// Plans & top-ups: segments, selectable cards, footer and the free-mode gate.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/main/subscribe_screen.dart';
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

PlanOption _p(String sku, String tier, String kind, String title, int paise, {int? was, double grant = 0, double stipend = 0}) => PlanOption(
      sku: sku, tier: tier, kind: kind, title: title, pricePaise: paise, priceUsdCents: null,
      billingInterval: kind == 'subscription' ? 'monthly' : null, cashGrant: grant, monthlyStipend: stipend, compareAtPaise: was,
    );

final _catalogue = [
  _p('pro_m', 'pro', 'subscription', 'Pro', 7450, was: 14900, stipend: 5000),
  _p('titan_m', 'titan', 'subscription', 'Titan', 39950, was: 79900, stipend: 20000),
  _p('topup_plus', 'free', 'topup', 'Plus Pack', 29950, was: 59900, grant: 100000),
  _p('topup_mini', 'free', 'topup', 'Mini Pack', 2900, grant: 5000),
];

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
    child: MaterialApp(theme: AppTheme.darkTheme, home: SubscribeScreen(catalogue: _catalogue)),
  ));
  await tester.pumpAndSettle();
}

ElevatedButton _pay(WidgetTester tester) => tester.widget<ElevatedButton>(find.ancestor(of: find.text('Pay with UPI'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)));

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'plans-test-key');
  });

  tearDown(() => AppFlagsService.instance.debugSetFlag('monetization_enabled', false));

  testWidgets('free mode shows the educational screen', (tester) async {
    AppFlagsService.instance.debugSetFlag('monetization_enabled', false);
    await _pump(tester);
    expect(find.text('Educational Mode'), findsOneWidget);
  });

  testWidgets('subscriptions: starter is current, Pro preselected, struck price, pay enabled', (tester) async {
    AppFlagsService.instance.debugSetFlag('monetization_enabled', true);
    await _pump(tester);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('POPULAR'), findsOneWidget);
    expect(find.text('FLAGSHIP'), findsOneWidget);
    expect(find.text('50% OFF'), findsWidgets);
    expect(find.text('Pro · per month'), findsOneWidget, reason: 'cheapest paid plan is the default pick');
    expect(_pay(tester).onPressed, isNotNull);
    final llp = find.textContaining('Kashivwealth Management LLP');
    await tester.scrollUntilVisible(llp, 150, scrollable: find.byType(Scrollable).first);
    expect(llp, findsOneWidget);
    await tester.scrollUntilVisible(find.text('Titan'), -150, scrollable: find.byType(Scrollable).first);

    await tester.tap(find.text('Titan'));
    await tester.pump();
    expect(find.text('Titan · per month'), findsOneWidget);
  });

  testWidgets('top-ups list one-time packs and switch the footer', (tester) async {
    AppFlagsService.instance.debugSetFlag('monetization_enabled', true);
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Top-ups'));
    await tester.pumpAndSettle();
    expect(find.text('Starter'), findsNothing);
    expect(find.text('TOP-UP'), findsOneWidget);
    expect(find.text('Mini Pack · one-time'), findsOneWidget, reason: 'cheapest pack first');
    await tester.tap(find.text('Plus Pack'));
    await tester.pump();
    expect(find.text('Plus Pack · one-time'), findsOneWidget);
    expect(find.textContaining('GPay · PhonePe'), findsOneWidget);
  });
}
