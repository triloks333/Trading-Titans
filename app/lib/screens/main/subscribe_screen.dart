import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class SubscribeScreen extends StatelessWidget {
  const SubscribeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final wallet = auth.user?.walletBalance ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top up your wallet'),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current balance', style: TextStyle(color: AppColors.ink4, fontSize: 13)),
            const SizedBox(height: AppSpacing.xs),
            Text('₹${wallet.toStringAsFixed(0)}', style:       TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.lg),
                  Text('Select a demo top-up plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView(
                children: [
                  _planCard(context, 'Starter Boost', 199, 100000, true),
                  const SizedBox(height: AppSpacing.sm),
                  _planCard(context, 'Titan Plus', 599, 500000, false),
                  const SizedBox(height: AppSpacing.sm),
                  _planCard(context, 'Pro Launch', 999, 1000000, false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(BuildContext context, String title, int price, int cash, bool popular) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.birch),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (popular)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(color: AppColors.imperialGold, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child:       Text('MOST POPULAR', style: TextStyle(color: AppColors.pureWhite, fontSize: 10)),
            ),
          if (popular) const SizedBox(height: AppSpacing.sm),
          Text(title, style:       TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.xs),
          Text('₹$cash demo cash', style:       TextStyle(color: AppColors.ink4)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹$price', style:       TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              ElevatedButton(
                onPressed: () {
                  _showBetaPhaseDialog(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold),
                child:       Text('Top up', style: TextStyle(color: AppColors.pureWhite)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBetaPhaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.pureWhite,
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.imperialGold, size: 28),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Beta Testing Phase',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Text(
          'We have currently paused the paywall for the beta testing phase. To get more credits, kindly contact the mods.',
          style: GoogleFonts.inter(
            color: AppColors.ink3,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.imperialGold,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            ),
            child: Text(
              'Got it',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

