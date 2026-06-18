import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/supabase_config.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main/main_navigation.dart';
import 'screens/auth/reset_password_screen.dart';
import 'widgets/update_dialogs.dart';
import 'package:showcaseview/showcaseview.dart';
import 'services/firebase_service.dart';
import 'services/remote_config_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  await FirebaseService.instance.initialize();
  await RemoteConfigService.instance.initialize();
  runApp(const TradingTitansApp());
}

/// The gate that should currently be shown to the user, in priority order.
///
/// Precedence (R8.1, R8.2, R10.8): a still-initializing app shows [loading];
/// once initialized, maintenance wins over a hard update, which in turn wins
/// over the normal app flow.
enum ActiveGate { loading, maintenance, hardUpdate, normal }

/// Pure helper that selects which gate to display from the current evaluation
/// flags. Kept top-level and side-effect free so the precedence (notably
/// maintenance > hard update, R10.8) is independently testable.
ActiveGate selectActiveGate({
  required bool isInitializing,
  required bool needsMaintenanceMode,
  required bool needsHardUpdate,
}) {
  if (isInitializing) return ActiveGate.loading;
  if (needsMaintenanceMode) return ActiveGate.maintenance;
  if (needsHardUpdate) return ActiveGate.hardUpdate;
  return ActiveGate.normal;
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
          Widget homeWidget;
          switch (selectActiveGate(
            isInitializing: auth.isInitializing,
            needsMaintenanceMode: auth.needsMaintenanceMode,
            needsHardUpdate: auth.needsHardUpdate,
          )) {
            case ActiveGate.loading:
              homeWidget = const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
              break;
            case ActiveGate.maintenance:
              homeWidget = MaintenanceScreen(message: auth.maintenanceMessage);
              break;
            case ActiveGate.hardUpdate:
              homeWidget = HardUpdateGate(
                updateUrl: auth.updateUrl,
                releaseNotes: auth.latestVersionNotes,
              );
              break;
            case ActiveGate.normal:
              homeWidget = auth.isRecoveringPassword
                  ? const ResetPasswordScreen()
                  : auth.isAuthenticated
                      // ignore: deprecated_member_use
                      ? ShowCaseWidget(builder: (context) => const MainNavigation())
                      : const LoginScreen();
              break;
          }

          return MaterialApp(
            title: 'Trading Titans',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.themeMode,
            navigatorKey: AuthService.navigatorKey,
            home: AppLifecycleGate(child: homeWidget),
            navigatorObservers: FirebaseService.instance.isInitialized
                ? [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
                : [],
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

/// Lives for the whole app session and re-evaluates the update/maintenance
/// gating whenever the app returns to the foreground, so a newly-flipped
/// maintenance or hard-update flag is applied before the user regains access
/// (R10.6, R10.7).
class AppLifecycleGate extends StatefulWidget {
  const AppLifecycleGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLifecycleGate> createState() => _AppLifecycleGateState();
}

class _AppLifecycleGateState extends State<AppLifecycleGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Retains last-known gating states if the refresh fails (R10.7).
      context.read<AuthService>().reevaluate();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
