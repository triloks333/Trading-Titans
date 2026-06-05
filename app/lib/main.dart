import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/supabase_config.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main/main_navigation.dart';
import 'package:showcaseview/showcaseview.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  runApp(const TradingTitansApp());
}

class TradingTitansApp extends StatelessWidget {
  const TradingTitansApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..initialize()),
        ChangeNotifierProvider(create: (_) => ThemeService()..initialize()),
      ],
      child: Consumer2<AuthService, ThemeService>(
        builder: (context, auth, themeService, child) {
          if (auth.isInitializing) {
            return MaterialApp(
              title: 'Trading Titans',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeService.themeMode,
              home: const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              debugShowCheckedModeBanner: false,
            );
          }

          return MaterialApp(
            title: 'Trading Titans',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.themeMode,
            home: auth.isAuthenticated
                // ignore: deprecated_member_use
                ? ShowCaseWidget(builder: (context) => const MainNavigation())
                : const LoginScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
