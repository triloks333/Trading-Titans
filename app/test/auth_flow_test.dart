// Behaviour of the rebuilt Welcome / Sign in / Create account flow. Runs against
// an unroutable local Supabase: every assertion here is decided before any
// network call (navigation, consent gate, password meter).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/auth/register_screen.dart';
import 'package:mobile/screens/auth/welcome_screen.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/theme_service.dart';

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthService()),
      ChangeNotifierProvider.value(value: ThemeService()),
    ],
    child: MaterialApp(theme: AppTheme.darkTheme, home: home),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Realistic-width stand-ins for IBM Plex (see screens_smoke_test.dart).
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

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', anonKey: 'auth-flow-test-key');
  });

  testWidgets('Welcome: Continue reaches the balance slide, which offers sign-up', (tester) async {
    await _pump(tester, const WelcomeScreen());
    expect(find.text('Real markets.\nVirtual stakes.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('YOUR STARTING BALANCE'), findsOneWidget);
    expect(find.text('Create free account'), findsOneWidget);

    await tester.tap(find.text('Create free account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('Welcome: Sign in opens the sign-in screen with a back button', (tester) async {
    await _pump(tester, const WelcomeScreen());
    await tester.tap(find.text('Sign in').first);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });

  testWidgets('Sign in <-> Create account switch swaps the screens', (tester) async {
    await _pump(tester, const LoginScreen());
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('Google without consent shows the consent error instead of signing in', (tester) async {
    await _pump(tester, const LoginScreen());
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(find.textContaining('accept', findRichText: true), findsWidgets);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Sign in')).onPressed, isNotNull,
        reason: 'no sign-in started, so the form is not busy');
  });

  testWidgets('Create account: meter follows the password, button needs 8 characters', (tester) async {
    await _pump(tester, const RegisterScreen());
    Finder button() => find.widgetWithText(ElevatedButton, 'Create account');
    expect(find.text('At least 8 characters'), findsWidgets); // field hint + meter
    expect(tester.widget<ElevatedButton>(button()).onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(2), 'Abcdef1!');
    await tester.pump();
    expect(find.text('Password strength: Strong'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(button()).onPressed, isNotNull);
  });
}
