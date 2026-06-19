import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_service.dart';
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
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppColors.warmWhite,
            border: Border(top: BorderSide(color: AppColors.birch)),
            boxShadow: AppShadows.sm,
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.warmWhite,
            selectedItemColor: AppColors.imperialGold,
            unselectedItemColor: AppColors.ink5,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
            elevation: 0,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
              BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_outlined), activeIcon: Icon(Icons.swap_horiz), label: 'Trade'),
              BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: 'Portfolio'),
              BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}
