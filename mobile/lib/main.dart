import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/supabase_config.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main/main_navigation.dart';

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
    return ChangeNotifierProvider(
      create: (_) => AuthService()..initialize(),
      child: Consumer<AuthService>(
        builder: (context, auth, child) {
          if (auth.isInitializing) {
            return MaterialApp(
              title: 'Trading Titans',
              theme: AppTheme.lightTheme,
              home: const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
              debugShowCheckedModeBanner: false,
            );
          }

          return MaterialApp(
            title: 'Trading Titans',
            theme: AppTheme.lightTheme,
            home: auth.isAuthenticated ? const MainNavigation() : const LoginScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
