import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../core/app_constants.dart';
import '../../widgets/crown_logo.dart';
import '../../core/rate_prompt.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
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
    // Initial check after a brief load delay
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      _checkRewards();
      _checkSoftUpdate();
      CountryCurrencyUpdateDialog.checkAndShow(context);
      _maybeAskForRating();
      SupabaseService().evaluatePriceAlerts();
    });
  }

  void _onTourReplay() {
    if (!mounted) return;
    setState(() => _currentIndex = 0);
  }

  void _onTabRequest() {
    final i = NavTabService.tabRequest.value;
    // Derived from NavTabService.count, not a literal, so a new destination is
    // reachable from a deep link the moment it is added.
    if (!mounted || i < 0 || i >= NavTabService.count) return;
    setState(() => _currentIndex = i);
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
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            content: Text(
              'Are you sure you want to exit the application?',
              style: GoogleFonts.inter(color: AppColors.ink3),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.ink4, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bear,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Exit', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
                onTap: (index) => setState(() => _currentIndex = index),
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
              onTap: (index) => setState(() => _currentIndex = index),
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
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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
                  style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  Money.wallet(user?.walletBalance ?? 0),
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  'Demo cash',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.ink4),
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
                  style: GoogleFonts.inter(
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
  NavDest(Icons.dashboard_outlined, Icons.dashboard_rounded, 'Home'),
  NavDest(Icons.swap_horiz_outlined, Icons.swap_horiz_rounded, 'Trade'),
  NavDest(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Portfolio'),
  NavDest(Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded, 'Wallet'),
  // The leaderboard. CompeteScreen was written but never wired to anything —
  // no import, no route — so it had been unreachable in the shipped app.
  NavDest(Icons.emoji_events_outlined, Icons.emoji_events_rounded, 'League'),
  NavDest(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

/// Floating, glassy navbar with an animated "expanding pill" for the active
/// item. Theme-aware via AppColors (works in both light and dark). It lives in
/// the bottomNavigationBar slot so its height stays reserved — no screen
/// content is ever hidden behind it.
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({required this.currentIndex, required this.onTap});

  static const List<NavDest> _dests = kMainNavDests;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.pureWhite.withValues(alpha: dark ? 0.92 : 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.birch),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: dark ? 0.55 : 0.16),
              blurRadius: 28,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        // One equal slot per destination. Expanded is what makes the bar
        // width-proof: with six items the previous design — icon-only until
        // selected, then expanding to reveal a label — wanted about 400dp on a
        // 360dp phone, so it had to be scaled down to fit and came out cramped.
        // Fixed slots with a small permanent label read better at six and cannot
        // overflow at any width.
        child: Row(
          children: List.generate(_dests.length, (i) {
            return Expanded(
              child: _NavButton(
                dest: _dests[i],
                selected: i == currentIndex,
                onTap: () => onTap(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavButton({required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color activeColor = AppColors.imperialGold;
    final Color idleColor = AppColors.ink4;
    return Semantics(
      // The label is small and the icons are the primary signal, so it is stated
      // here explicitly rather than left to a screen reader to infer.
      label: dest.label,
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The pill hugs the icon only. Sizing it to the whole slot would put
            // six touching blocks of gold across the bar.
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? AppColors.goldPale : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? dest.activeIcon : dest.icon,
                size: 21,
                color: selected ? activeColor : idleColor,
              ),
            ),
            const SizedBox(height: 3),
            // Always visible, so no destination is a guessing game — which is the
            // trade the old expand-on-select design was making. Clipped rather
            // than wrapped: a second line would change the bar's height as the
            // user moves between tabs.
            Text(
              dest.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : idleColor,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
