import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme.dart';
import 'core/supabase_config.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/main/main_navigation.dart';
import 'screens/auth/reset_password_screen.dart';
import 'widgets/update_dialogs.dart';
import 'widgets/web_page.dart';
import 'package:showcaseview/showcaseview.dart';
import 'services/firebase_service.dart';
import 'services/remote_config_service.dart';
import 'services/app_flags_service.dart';
import 'services/plan_service.dart';
import 'services/currency_service.dart';
import 'services/supabase_service.dart';
import 'services/churn_telemetry_service.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/main/convert_account_screen.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'services/price_store.dart';

Future<void> main() async {
  ChurnTelemetryService.processStart = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  await FirebaseService.instance.initialize();
  await RemoteConfigService.instance.initialize();
  // Read the cached currency choice before the first frame, so the app never
  // renders rupees at a user who picked dollars.
  await CurrencyService.instance.loadCached();
  await ChurnTelemetryService.instance.init();
  ChurnTelemetryService.instance.recordAppLaunch(source: 'app_launch');
  await ChurnTelemetryService.instance.recordSessionStart();
  // Live prices over Realtime; off while backgrounded or when the
  // `realtime_prices_enabled` flag is false.
  PriceStore.instance.start();
  runApp(const TradingTitansApp());
}

/// Refreshes the DB-backed flags and advances the daily login streak.
///
/// Both are safe to call repeatedly: the flag read is a plain select, and
/// `touch_login_streak()` is a no-op once it has already counted today.
Future<void> _refreshSessionState() async {
  await AppFlagsService.instance.refresh();
  // Before anything prices a derivative: an exchange holiday closes the Indian
  // session, and a closed session is what stops synthetic F&O prices drifting
  // against the wall clock.
  await SupabaseService().refreshMarketHolidays();
  await CurrencyService.instance.refresh();
  // The plan drives the badge and the paid-feature gates. Refreshed here so a
  // renewal or a cancellation that happened on the web is picked up on the next
  // foreground, without the user having to reinstall or sign out.
  await PlanService.instance.refresh();
  await SupabaseService().touchLoginStreak();
  await SupabaseService().recordPlatform(platformTag());
}

/// The platform name for `record_platform`.
///
/// Derived from [defaultTargetPlatform] rather than `Platform.operatingSystem`
/// because `dart:io` does not exist on web, which is one of the three answers we
/// care about. Sends the real platform name even for platforms we do not ship —
/// the RPC lowercases what it recognises and silently ignores the rest, so a
/// desktop build reads as unknown instead of quietly inflating Android.
///
/// Deliberately not tied to push-token registration: that only runs once FCM
/// hands over a token, so it would miss every web user and everyone who declined
/// notifications, and count them as having no platform at all.
String platformTag() =>
    kIsWeb ? 'web' : defaultTargetPlatform.name; // 'iOS' → RPC lowercases it.

/// The gate that should currently be shown to the user, in priority order.
///
/// Precedence (R8.1, R8.2, R10.8): a still-initializing app shows [loading];
/// once initialized, maintenance wins over a hard update, which in turn wins
/// over the normal app flow.
enum ActiveGate { loading, maintenance, hardUpdate, onboarding, normal }

/// Pure helper that selects which gate to display from the current evaluation
/// flags. Kept top-level and side-effect free so the precedence (notably
/// maintenance > hard update, R10.8) is independently testable.
/// Onboarding sits *below* maintenance and hard-update — there is no point
/// asking a user their preferred currency on a build we are about to block — but
/// *above* the normal app, because the first-run questions must be answered
/// before the home screen. It only applies to a signed-in user.
ActiveGate selectActiveGate({
  required bool isInitializing,
  required bool needsMaintenanceMode,
  required bool needsHardUpdate,
  bool isAuthenticated = false,
  bool needsOnboarding = false,
}) {
  if (isInitializing) return ActiveGate.loading;
  if (needsMaintenanceMode) return ActiveGate.maintenance;
  if (needsHardUpdate) return ActiveGate.hardUpdate;
  if (isAuthenticated && needsOnboarding) return ActiveGate.onboarding;
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
        ChangeNotifierProvider.value(value: AppFlagsService.instance),
        ChangeNotifierProvider.value(value: CurrencyService.instance),
        ChangeNotifierProvider.value(value: PlanService.instance),
      ],
      child: Consumer3<AuthService, ThemeService, CurrencyService>(
        builder: (context, auth, themeService, currency, child) {
          Widget homeWidget;
          // True only for the signed-in app, which brings its own desktop
          // chrome. Everything else is a single form and gets capped narrower.
          bool hasAppChrome = false;
          switch (selectActiveGate(
            isInitializing: auth.isInitializing,
            needsMaintenanceMode: auth.needsMaintenanceMode,
            needsHardUpdate: auth.needsHardUpdate,
            isAuthenticated: auth.isAuthenticated,
            // Only gate once the cached preference has loaded, so a cold start
            // does not flash onboarding at a user who already answered.
            needsOnboarding:
                currency.isLoaded && !currency.onboardingComplete,
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
            case ActiveGate.onboarding:
              homeWidget = const OnboardingScreen();
              break;
            case ActiveGate.normal:
              hasAppChrome = auth.isAuthenticated && !auth.isGuest && !auth.isRecoveringPassword;
              homeWidget = auth.isRecoveringPassword
                  ? const ResetPasswordScreen()
                  : !auth.isAuthenticated
                      ? const WelcomeScreen()
                      // Guests finish onboarding on a guest session, then must sign up or sign in.
                      : auth.isGuest
                          ? const ConvertAccountScreen(requiredGate: true)
                          // ignore: deprecated_member_use
                          : ShowCaseWidget(builder: (context) => const MainNavigation());
              break;
          }
          if (!hasAppChrome) homeWidget = webFormPage(homeWidget);

          return MaterialApp(
            title: 'Trading Titans',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.themeMode,
            navigatorKey: AuthService.navigatorKey,
            // Max scroll depth per screen for the analytics dashboard.
            // Scroll depth, pull-to-refresh and dead taps for the analytics dashboard.
            builder: (context, child) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: ChurnTelemetryService.instance.onPointerDown,
              onPointerUp: ChurnTelemetryService.instance.onPointerUp,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  ChurnTelemetryService.instance.recordScrollNotification(n);
                  return false;
                },
                child: webShell(child),
              ),
            ),
            home: AppLifecycleGate(child: homeWidget),
            navigatorObservers: [
              ChurnTelemetryNavigatorObserver(),
              if (FirebaseService.instance.isInitialized)
                FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
            ],
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

/// Paints the page background behind the app in a desktop browser.
///
/// Deliberately does NOT cap the width. An earlier version did, and the result
/// was that every page — including the sign-in form — became a narrow strip with
/// dead gutters either side, which is precisely what makes a web app look like a
/// phone app in a browser. Width is now decided per page by whoever knows what
/// the page is: [MainNavigation] caps its own shell, and [webFormPage] gives the
/// form pages a full-bleed split layout.
///
/// Hung off `MaterialApp.builder` rather than wrapped around `home`, so dialogs
/// and pushed routes sit on the same background.
///
/// Mobile is untouched: [kIsWeb] is false there and the child is returned as-is.
Widget webShell(Widget? child) {
  final content = child ?? const SizedBox.shrink();
  if (!kIsWeb) return content;
  return ColoredBox(color: AppColors.parchment, child: content);
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
  /// Guards the one-shot post-login refresh so it fires on the sign-in edge
  /// rather than on every rebuild.
  bool _sessionStateLoaded = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Flags and the login streak both need a session, so they wait for auth.
    final authenticated = context.watch<AuthService>().isAuthenticated;
    if (authenticated && !_sessionStateLoaded) {
      _sessionStateLoaded = true;
      _refreshSessionState();
    } else if (!authenticated) {
      _sessionStateLoaded = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Uploads events and computed metrics; without it the dashboard stays empty.
      ChurnTelemetryService.instance.flushToBackend();
      ChurnTelemetryService.instance.recordCleanExit();
    }
    if (state == AppLifecycleState.resumed) {
      ChurnTelemetryService.instance.recordAppLaunch(source: 'resume');
      ChurnTelemetryService.instance.resumeAfterPause();
      // Retains last-known gating states if the refresh fails (R10.7).
      context.read<AuthService>().reevaluate();
      if (context.read<AuthService>().isAuthenticated) {
        // Picks up a flag flipped in the backend, and rolls the streak over if
        // the app was left open past midnight IST.
        _refreshSessionState();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
