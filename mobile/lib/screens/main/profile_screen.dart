import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/crown_logo.dart';
import 'subscribe_screen.dart';
import 'orders_screen.dart';
import 'analytics_screen.dart';
import 'autopsy_screen.dart';
import 'whatif_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: AppCard.primary,
              child: Column(
                children: [
                  const CrownLogo(size: 56, withRing: true),
                  const SizedBox(height: AppSpacing.md),
                  Text(user?.name ?? 'Titan', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(user?.email ?? 'you@domain.com', style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink4)),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                    decoration: AppCard.badge(user?.subscriptionActive == true ? AppColors.bullLight : AppColors.cream),
                    child: Text(
                      user?.subscriptionActive == true ? 'ACTIVE' : 'FREE STARTER',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: user?.subscriptionActive == true ? AppColors.bull : AppColors.ink4, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _detailRow('Wallet Balance', '₹${user?.walletBalance.toStringAsFixed(0) ?? '0'}'),
                  const SizedBox(height: AppSpacing.sm),
                  _detailRow('Total P&L', '₹${user?.totalRealizedPnl.toStringAsFixed(0) ?? '0'}',
                      valueColor: (user?.totalRealizedPnl ?? 0) >= 0 ? AppColors.bull : AppColors.bear),
                  const SizedBox(height: AppSpacing.sm),
                  _detailRow('Member Since', user != null ? user.createdAt.toLocal().toShortDateString() : '-'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscribeScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.imperialGold,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text('Top up Demo Cash', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.pureWhite, letterSpacing: 0.5)),
            ),
            const SizedBox(height: AppSpacing.lg),
            _menuItem(context, Icons.bar_chart, 'Analytics', const AnalyticsScreen()),
            _menuItem(context, Icons.receipt_long, 'Order History', const OrdersScreen()),
            _menuItem(context, Icons.lightbulb_outline, 'What-If Simulator', const WhatIfScreen()),
            _menuItem(context, Icons.medical_services_outlined, 'Loss Autopsy', const AutopsyScreen()),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () async {
                await auth.logout();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.bear),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text('Sign Out', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.bear, letterSpacing: 0.5)),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Center(child: Text('Trading Titans v1.1', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5))),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, Widget screen) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: AppSpacing.lg),
          side: const BorderSide(color: AppColors.birch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          backgroundColor: AppColors.pureWhite,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink2),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: GoogleFonts.inter(color: AppColors.ink, fontWeight: FontWeight.w500))),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink4),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 13)),
        Text(value, style: GoogleFonts.inter(color: valueColor ?? AppColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

extension on DateTime {
  String toShortDateString() {
    return '$day/${month.toString().padLeft(2, '0')}/${year.toString().substring(2)}';
  }
}
