import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/pro_pass_offer_dialog.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../core/app_constants.dart';
import '../../widgets/crown_logo.dart';
import '../../core/rate_prompt.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
import '../../services/currency_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/action_reaction_engine.dart';
import '../../services/tour_service.dart';
import '../../services/nav_tab_service.dart';
import '../../widgets/reward_celebration_dialog.dart';
import '../../widgets/update_dialogs.dart';
import '../../widgets/country_currency_update_dialog.dart';
import 'dashboard_screen.dart';
import 'trade_screen.dart';
import 'portfolio_screen.dart';
import 'wallet_screen.dart';
import 'compete_screen.dart';
import 'profile_screen.dart';
import 'autopsy_screen.dart';
import 'convert_account_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  Timer? _rewardCheckTimer;
  bool _showingReward = false;

  /// Whether the soft-update prompt has already been offered this session.
  bool _softUpdatePrompted = false;

  /// Held so the listener can be removed in [dispose] (`context` is unsafe to
  /// look up there).
  AuthService? _auth;

  @override
  void initState() {
    super.initState();
    // When a tour replay is requested (e.g. from Profile), jump to the Home
    // tab. Switching to index 0 recreates the dashboard, which then reads the
    // pending-replay flag and starts the tour.
    TourService.goHomeTick.addListener(_onTourReplay);
    NavTabService.tabRequest.addListener(_onTabRequest);
    // Catch the soft-update flag turning on *after* launch. The resume
    // re-evaluation in AppLifecycleGate arms it long after initState, and
    // without this the dialog never appeared until the app was fully restarted.
    _auth = context.read<AuthService>();
    _auth?.addListener(_checkSoftUpdate);
    // Check for unclaimed rewards every 10 seconds
    _rewardCheckTimer = Timer.periodic(AppConstants.rewardCheckPoll, (_) {
      _checkRewards();
      SupabaseService().evaluatePriceAlerts();
    });
    ChurnTelemetryService.instance.recordHomeScreen(_tabScreens[_currentIndex]);
    // Initial check after a brief load delay
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _intelStartup();
      _checkRewards();
      _checkSoftUpdate();
      CountryCurrencyUpdateDialog.checkAndShow(context);
      _maybeAskForRating();
      SupabaseService().evaluatePriceAlerts();
    });
    // The 7-day Pro pass offer, after the launch prompts have had their turn.
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted || _showingReward || context.read<AuthService>().needsSoftUpdate) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      ProPassOffer.maybeShow(context);
    });
  }

  static const _tabScreens = ['dashboard_screen', 'trade_screen', 'portfolio_screen', 'wallet_screen', 'compete_screen', 'profile_screen'];

  void _setTab(int i) {
    setState(() => _currentIndex = i);
    ChurnTelemetryService.instance.recordHomeScreen(_tabScreens[i.clamp(0, _tabScreens.length - 1)]);
  }

  /// Feeds account state into the health metrics and claims a pending crash
  /// apology (the server decides whether it is owed).
  Future<void> _intelStartup() async {
    final auth = context.read<AuthService>();
    final u = auth.user;
    if (u != null) {
      final providers = (Supabase.instance.client.auth.currentUser?.appMetadata['providers'] as List?) ?? const [];
      final darkMode = context.read<ThemeService>().isDarkMode;
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final stats = await SupabaseService().getGamificationStats();
      final phone = await _profilePhone();
      ChurnTelemetryService.instance.updateLive(
        walletBalance: u.walletBalance,
        startingCash: auth.isGuest ? 5000 : 11000,
        isGuest: auth.isGuest,
        oauth: providers.contains('google') || providers.contains('apple'),
        darkMode: darkMode,
        textScale: textScale,
        countryCode: CurrencyService.instance.countryCode,
        hasPhone: phone,
        totalXp: stats['total_xp'] ?? 0,
      );
    }
    final engine = ActionReactionEngine.instance;
    final r = await engine.claimCrashApologyIfPending() ?? await engine.startupReactions(isGuest: auth.isGuest);
    if (r == null || !mounted) return;
    if (r.key == 'crash_apology') await auth.refreshUser();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.text),
      duration: const Duration(seconds: 8),
      action: r.action == null
          ? null
          : SnackBarAction(
              label: r.actionLabel!,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => r.action == 'convert' ? const ConvertAccountScreen() : const AutopsyScreen())),
            ),
    ));
  }

  /// Whether the profile has a saved mobile number (for the funnel metrics).
  Future<bool> _profilePhone() async {
    try {
      final client = Supabase.instance.client;
      final row = await client.from('profiles').select('phone').eq('id', client.auth.currentUser!.id).maybeSingle();
      return '${row?['phone'] ?? ''}'.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _onTourReplay() {
    if (!mounted) return;
    _setTab(0);
  }

  void _onTabRequest() {
    final i = NavTabService.tabRequest.value;
    // Derived from NavTabService.count, not a literal, so a new destination is
    // reachable from a deep link the moment it is added.
    if (!mounted || i < 0 || i >= NavTabService.count) return;
    _setTab(i);
  }

  /// Offers the soft update, at most once per app session.
  ///
  /// Called both from the post-launch one-shot and from the [AuthService]
  /// listener, so a prompt armed mid-session (the resume re-evaluation in
  /// `AppLifecycleGate`) is shown without needing a full restart.
  ///
  /// The once-per-session guard also stops a barrier tap — which closes the
  /// dialog without recording a snooze — from immediately re-opening it.
  void _checkSoftUpdate() {
    if (!mounted || _softUpdatePrompted) return;
    final auth = context.read<AuthService>();
    if (!auth.needsSoftUpdate) return;
    _softUpdatePrompted = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => SoftUpdateDialog(
        updateUrl: auth.updateUrl,
        releaseNotes: auth.latestVersionNotes,
        onDismiss: () {
          auth.dismissSoftUpdate();
        },
      ),
    );
  }

  /// Asks for a Play Store rating once the user is on their second day back.
  ///
  /// Yields to the update prompt and the reward celebration, which own the
  /// screen when they fire. Staying silent costs nothing: no snooze is written,
  /// so the ask simply returns on a later launch.
  Future<void> _maybeAskForRating() async {
    if (!mounted) return;
    // Read before the awaits below, while the context is known-good.
    if (context.read<AuthService>().needsSoftUpdate || _showingReward) return;

    final stats = await SupabaseService().getGamificationStats();
    if (!await RatePrompt.shouldShowNow(stats['login_streak'] ?? 0)) return;
    if (!mounted || _showingReward) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => RateAppDialog(
        storeUrl: AppConstants.playStoreUrl,
        onRateNow: RatePrompt.markRated,
        onRemindLater: RatePrompt.snooze,
      ),
    );
  }

  @override
  void dispose() {
    TourService.goHomeTick.removeListener(_onTourReplay);
    NavTabService.tabRequest.removeListener(_onTabRequest);
    _auth?.removeListener(_checkSoftUpdate);
    _rewardCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkRewards() async {
    if (_showingReward || !mounted) return;
    try {
      final rewards = await SupabaseService().checkUnclaimedRewards();
      if (rewards.isNotEmpty && mounted) {
        final reward = rewards.first;
        final rewardId = reward['id'] as String;
        final amount = (reward['amount'] as num).toDouble();
        final message = reward['message'] as String? ?? 'You received a reward!';

        setState(() => _showingReward = true);

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogCtx) => RewardCelebrationDialog(
              amount: amount,
              message: message,
              onClose: () async {
                Navigator.of(dialogCtx).pop();
                try {
                  await SupabaseService().claimReward(rewardId, amount);
                  if (mounted) {
                    await context.read<AuthService>().refreshUser();
                  }
                } catch (_) {}
                if (mounted) {
                  setState(() => _showingReward = false);
                }
              },
            ),
          );
        }
      }
    } catch (_) {}
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const TradeScreen();
      case 2:
        return const PortfolioScreen();
      case 3:
        return const WalletScreen();
      case 4:
        return const CompeteScreen();
      case 5:
        return const ProfileScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // On mobile, back at the root asks before leaving the app. In a browser
      // that is wrong twice over: it hijacks the back button, and
      // SystemNavigator.pop() cannot close a tab — so the dialog's Exit button
      // would do nothing at all.
      canPop: kIsWeb,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: AppColors.pureWhite,
            title: Text(
              'Exit Trading Titans?',
              style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            content: Text(
              'Are you sure you want to exit the application?',
              style: GoogleFonts.ibmPlexSans(color: AppColors.ink3),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text('Cancel', style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bear,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Exit', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          await SystemNavigator.pop();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Desktop browser: sidebar beside the content. Gated on kIsWeb so a
          // large Android tablet keeps the shipped phone layout.
          if (kIsWeb && constraints.maxWidth >= AppConstants.webBreakpoint) {
            return _desktopScaffold();
          }
          return Scaffold(
            body: _getScreen(_currentIndex),
            bottomNavigationBar: Consumer<ThemeService>(
              // Rebuild the navbar the instant the theme toggles so its colours
              // track the app theme without needing a tab switch first.
              builder: (context, _, _) => _FloatingNavBar(
                currentIndex: _currentIndex,
                onTap: _setTab,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Desktop layout: a persistent sidebar and a readable content column.
  ///
  /// The screens themselves are reused untouched. They are single-column card
  /// lists built for a phone, so they are capped at [_kContentColumn] rather
  /// than stretched — a card list a thousand pixels wide reads worse than a
  /// narrow one, and stretching would have meant re-laying-out all five tabs.
  Widget _desktopScaffold() {
    return Scaffold(
      backgroundColor: AppColors.birch,
      // Capped here rather than around the whole app, so the sign-in split
      // screen can still run full-bleed. Centred, so a very wide monitor gets
      // even gutters instead of the app hugging the left edge.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: AppConstants.webMaxContentWidth),
          child: _desktopBody(),
        ),
      ),
    );
  }

  Widget _desktopBody() {
    return ColoredBox(
      color: AppColors.parchment,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Consumer<ThemeService>(
            builder: (context, _, _) => _DesktopSidebar(
              currentIndex: _currentIndex,
              onTap: _setTab,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kContentColumn),
                child: _getScreen(_currentIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Width of the sidebar on desktop.
const double _kSidebarWidth = 232;

/// Width the reused phone screens are capped at inside the desktop content area.
///
/// Sized so sidebar + content fills [AppConstants.webMaxContentWidth] exactly,
/// leaving no dead band. Still capped rather than unbounded: these screens are
/// single-column card lists, and a row stretched across a 2560px monitor puts
/// its left and right halves too far apart to read as one row.
const double _kContentColumn =
    AppConstants.webMaxContentWidth - _kSidebarWidth - 88;

/// Persistent left-hand navigation for the desktop browser layout.
///
/// The web equivalent of [_FloatingNavBar]: same [kMainNavDests], same indices,
/// so both drive [_MainNavigationState._getScreen] identically. Labels are
/// always visible here — there is room for them, and a sidebar of bare icons is
/// the thing that makes a web app feel like a phone port.
class _DesktopSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _DesktopSidebar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final guest = auth.isGuest;

    return Container(
      width: _kSidebarWidth,
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        border: Border(right: BorderSide(color: AppColors.birch)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
            child: Row(
              children: [
                const CrownLogo(size: 30),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Trading Titans',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < kMainNavDests.length; i++)
            _SidebarItem(
              dest: kMainNavDests[i],
              selected: i == currentIndex,
              onTap: () => onTap(i),
            ),
          const Spacer(),
          Divider(color: AppColors.birch, height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? 'Titan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  guest ? 'Guest account' : (user?.email ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  Money.wallet(user?.walletBalance ?? 0),
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'Demo cash',
                  style: GoogleFonts.ibmPlexSans(fontSize: 10, color: AppColors.ink4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.imperialGold : AppColors.ink3;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.imperialGold.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          // InkWell gives the pointer hover highlight a browser user expects,
          // for free, and only on platforms that have a pointer.
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 11),
            child: Row(
              children: [
                Icon(selected ? dest.activeIcon : dest.icon,
                    size: 20, color: color),
                const SizedBox(width: AppSpacing.md),
                Text(
                  dest.label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.ink : AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single destination in the app's primary navigation.
class NavDest {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const NavDest(this.icon, this.activeIcon, this.label);
}

/// The five primary destinations, in tab order.
///
/// Shared by the mobile floating navbar and the desktop sidebar so the two can
/// never drift apart — the index is what [_MainNavigationState._getScreen] and
/// [NavTabService.tabRequest] both key off.
const List<NavDest> kMainNavDests = [
  NavDest(Icons.home_outlined, Icons.home_rounded, 'Home'),
  NavDest(Icons.swap_vert_rounded, Icons.swap_vert_rounded, 'Trade'),
  NavDest(Icons.insert_chart_outlined_rounded, Icons.insert_chart_rounded, 'Portfolio'),
  NavDest(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
  // The leaderboard (CompeteScreen).
  NavDest(Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'League'),
  NavDest(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

/// Titan Terminal tab bar: docked flush to the bottom, one equal slot per
/// destination with a permanent label, so six tabs never overflow at 360dp.
/// Lives in the bottomNavigationBar slot so its height stays reserved.
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(top: BorderSide(color: AppColors.birch))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Row(children: [
              for (var i = 0; i < kMainNavDests.length; i++)
                Expanded(child: _NavButton(dest: kMainNavDests[i], selected: i == currentIndex, onTap: () {
                  ChurnTelemetryService.instance.recordButtonTap(const ['nav_tab_0_home', 'nav_tab_1_trade', 'nav_tab_2_portfolio', 'nav_tab_3_wallet', 'nav_tab_4_compete', 'nav_tab_5_profile'][i]);
                  onTap(i);
                })),
            ]),
          ),
        ),
      );
}

class _NavButton extends StatelessWidget {
  final NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavButton({required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.goldMid : AppColors.ink4;
    return Semantics(
      label: dest.label,
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: SizedBox(
          height: 52,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(selected ? dest.activeIcon : dest.icon, size: 22, color: color),
            const SizedBox(height: 3),
            // Clipped, never wrapped: a second line would change the bar height.
            Text(dest.label, maxLines: 1, softWrap: false, overflow: TextOverflow.clip,
                style: AppFonts.sans(size: 10.5, weight: selected ? FontWeight.w600 : FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}
