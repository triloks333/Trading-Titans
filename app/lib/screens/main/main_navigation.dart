import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/reward_celebration_dialog.dart';
import '../../widgets/update_dialogs.dart';
import 'dashboard_screen.dart';
import 'trade_screen.dart';
import 'portfolio_screen.dart';
import 'wallet_screen.dart';
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

  @override
  void initState() {
    super.initState();
    // Check for unclaimed rewards every 10 seconds
    _rewardCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkRewards();
      SupabaseService().evaluatePriceAlerts();
    });
    // Initial check after a brief load delay
    Future.delayed(const Duration(seconds: 2), () {
      _checkRewards();
      _checkSoftUpdate();
      SupabaseService().evaluatePriceAlerts();
    });
  }

  void _checkSoftUpdate() {
    final auth = context.read<AuthService>();
    if (auth.needsSoftUpdate && mounted) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => SoftUpdateDialog(
          updateUrl: auth.updateUrl,
          releaseNotes: auth.latestVersionNotes,
          onDismiss: () {
            auth.dismissSoftUpdate();
          },
        ),
      );
    }
  }

  @override
  void dispose() {
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
        return const ProfileScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
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
      child: Scaffold(
        body: _getScreen(_currentIndex),
        bottomNavigationBar: Consumer<ThemeService>(
          // Rebuild the navbar the instant the theme toggles so its colours
          // track the app theme without needing a tab switch first.
          builder: (context, _, _) => _FloatingNavBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
          ),
        ),
      ),
    );
  }
}

/// A single destination in the floating navbar.
class _NavDest {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavDest(this.icon, this.activeIcon, this.label);
}

/// Floating, glassy navbar with an animated "expanding pill" for the active
/// item. Theme-aware via AppColors (works in both light and dark). It lives in
/// the bottomNavigationBar slot so its height stays reserved — no screen
/// content is ever hidden behind it.
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({required this.currentIndex, required this.onTap});

  static const List<_NavDest> _dests = [
    _NavDest(Icons.dashboard_outlined, Icons.dashboard_rounded, 'Home'),
    _NavDest(Icons.swap_horiz_outlined, Icons.swap_horiz_rounded, 'Trade'),
    _NavDest(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Portfolio'),
    _NavDest(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
    _NavDest(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_dests.length, (i) {
            return _NavButton(
              dest: _dests[i],
              selected: i == currentIndex,
              onTap: () => onTap(i),
            );
          }),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  const _NavButton({required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color activeColor = AppColors.imperialGold;
    final Color idleColor = AppColors.ink4;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.goldPale : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? dest.activeIcon : dest.icon,
                size: 23,
                color: selected ? activeColor : idleColor,
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Text(
                  dest.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: activeColor,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
