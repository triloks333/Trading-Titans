// Smoke test for the Titan Terminal redesign: every screen must build and lay
// out without an exception (including RenderFlex overflow) in BOTH themes at a
// 390 x 844 phone size. Backend calls point at an unroutable local Supabase, so
// screens render their loading / empty / error states — which is exactly where
// layout regressions hide.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/market_hours.dart';
import 'package:mobile/core/theme.dart';
import 'package:mobile/services/app_flags_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/currency_service.dart';
import 'package:mobile/services/plan_service.dart';
import 'package:mobile/services/theme_service.dart';

import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/auth/onboarding_screen.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/screens/main/analytics_screen.dart';
import 'package:mobile/screens/main/autopsy_screen.dart';
import 'package:mobile/screens/main/challenges_screen.dart';
import 'package:mobile/screens/main/chat_screen.dart';
import 'package:mobile/screens/main/community_wishlist_screen.dart';
import 'package:mobile/screens/main/compete_screen.dart';
import 'package:mobile/screens/main/convert_account_screen.dart';
import 'package:mobile/screens/main/dashboard_screen.dart';
import 'package:mobile/models/quote.dart';
import 'package:mobile/screens/main/glossary_quiz_screen.dart';
import 'package:mobile/screens/main/option_chain_screen.dart';
import 'package:mobile/screens/main/order_entry_screen.dart';
import 'package:mobile/screens/main/stock_detail_screen.dart';
import 'package:mobile/screens/main/glossary_screen.dart';
import 'package:mobile/screens/main/muhurat_screen.dart';
import 'package:mobile/screens/main/news_list_screen.dart';
import 'package:mobile/screens/main/notifications_screen.dart';
import 'package:mobile/screens/main/orders_screen.dart';
import 'package:mobile/screens/main/portfolio_screen.dart';
import 'package:mobile/screens/main/profile_screen.dart';
import 'package:mobile/screens/main/refer_earn_screen.dart';
import 'package:mobile/screens/main/subscribe_screen.dart';
import 'package:mobile/screens/main/support_tickets_screen.dart';
import 'package:mobile/screens/main/trade_screen.dart';
import 'package:mobile/screens/main/wallet_screen.dart';
import 'package:mobile/screens/main/watchlist_screen.dart';
import 'package:mobile/screens/main/whatif_screen.dart';

Quote _reliance() => Quote(
      symbol: 'RELIANCE', yfSymbol: 'RELIANCE.NS', name: 'Reliance Industries', price: 2948.30,
      previousClose: 2915.65, change: 32.65, changePct: 1.12, currency: 'INR', market: 'stock',
      open: 2918.40, dayHigh: 2956.00, dayLow: 2911.10, volume: 6420000,
    );

final screens = <String, Widget Function()>{
  'Stock detail': () => const StockDetailScreen(symbol: 'RELIANCE', market: 'stock', name: 'Reliance Industries'),
  'Order entry · buy': () => OrderEntryScreen(quote: _reliance(), isBuy: true),
  'Order entry · sell': () => OrderEntryScreen(quote: _reliance(), isBuy: false),
  'Option chain': () => const OptionChainScreen(underlyingSymbol: 'NIFTY', spotPrice: 24318.45),
  'Onboarding': () => const OnboardingScreen(),
  'Login': () => const LoginScreen(),
  'Register': () => const RegisterScreen(),
  'Home': () => const DashboardScreen(),
  'Trade': () => const TradeScreen(),
  'Watchlists': () => const WatchlistScreen(),
  'Portfolio': () => const PortfolioScreen(),
  'Orders': () => const OrdersScreen(),
  'Wallet': () => const WalletScreen(),
  'Analytics': () => const AnalyticsScreen(),
  'Autopsy': () => const AutopsyScreen(),
  'What-If': () => const WhatIfScreen(),
  'League': () => const CompeteScreen(),
  'Challenges': () => const ChallengesScreen(),
  'Glossary': () => const GlossaryScreen(),
  'Glossary quiz': () => const GlossaryQuizScreen(),
  'Plans': () => const SubscribeScreen(),
  'Refer & earn': () => const ReferEarnScreen(),
  'Titans Room': () => const ChatScreen(),
  'Titans Room · Tickets': () => const ChatScreen(initialTab: 1),
  'Titans Room · Wishlist': () => const ChatScreen(initialTab: 2),
  'Support tickets': () => const SupportTicketsScreen(),
  'Community wishlist': () => const CommunityWishlistScreen(),
  'Profile': () => const ProfileScreen(),
  'Notifications': () => const NotificationsScreen(),
  'News': () => const NewsListScreen(posts: []),
  'Convert account': () => const ConvertAccountScreen(),
  'Muhurat': () => const MuhuratScreen(),
};

Future<void> _pump(WidgetTester tester, Widget screen, bool dark) async {
  await ThemeService().setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthService()),
      ChangeNotifierProvider.value(value: ThemeService()),
      ChangeNotifierProvider.value(value: AppFlagsService.instance),
      ChangeNotifierProvider.value(value: CurrencyService.instance),
      ChangeNotifierProvider.value(value: PlanService.instance),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      // Registered the same way main.dart does, for screens that host the app tour.
      // ignore: deprecated_member_use -- mirrors main.dart, which still registers it this way
      home: ShowCaseWidget(builder: (_) => screen),
    ),
  ));
  // Let initState futures fail against the dead backend and settle the UI.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// The test font draws every glyph 1em wide (about twice IBM Plex), which makes
/// overflow numbers meaningless. Register local Arial / Consolas, which are close
/// in width to IBM Plex Sans / Mono, under the family names google_fonts uses.
Future<void> _loadRealisticFonts() async {
  final sans = File('C:/Windows/Fonts/arial.ttf'), mono = File('C:/Windows/Fonts/consola.ttf');
  if (!sans.existsSync() || !mono.existsSync()) return; // non-Windows CI: keep test font
  final variants = ['regular', 'italic', for (final w in [100, 200, 300, 500, 600, 700, 800, 900]) ...['$w', '${w}italic']];
  for (final (family, file) in [('IBMPlexSans', sans), ('IBMPlexSerif', sans), ('IBMPlexMono', mono)]) {
    for (final v in variants) {
      final loader = FontLoader('${family}_$v')..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  }
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadRealisticFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'smoke-test-anon-key');
    // A live Muhurat session so its screen and card take the countdown path.
    final now = DateTime.now().toUtc();
    MarketHours.specialSessions = [
      SpecialSession(name: 'Muhurat Trading', start: now.add(const Duration(days: 2)), end: now.add(const Duration(days: 2, hours: 1))),
    ];
  });

  for (final dark in [true, false]) {
    group(dark ? 'dark' : 'light', () {
      for (final e in screens.entries) {
        testWidgets('${e.key} builds and lays out at 390x844', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = errors.add;
          try {
            await _pump(tester, e.value(), dark);
          } finally {
            FlutterError.onError = previous;
          }
          // Font assets are not bundled in tests; anything else is a real failure.
          // Font assets and the deliberately dead backend are not layout bugs.
          final real = errors.where((d) {
            final m = '${d.exception}';
            return !m.contains('google_fonts') && !m.contains('PostgrestException') && !m.contains('SocketException') &&
                !m.contains('ClientException') && !m.contains('AuthException') &&
                // showcaseview's tour tooltip animates against the fake test clock.
                !m.contains('elapsedInSeconds >= 0.0');
          }).toList();
          expect(real.map((d) => '${d.exception}'.split('\n').first).toList(), isEmpty,
              reason: '${e.key} (${dark ? 'dark' : 'light'})');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    });
  }
}
