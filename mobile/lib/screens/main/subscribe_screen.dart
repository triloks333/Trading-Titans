import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';

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
            Text('₹${wallet.toStringAsFixed(0)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.lg),
            const Text('Select a demo top-up plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView(
                children: [
                  _planCard(context, 'Starter Boost', 199, 50000, true),
                  const SizedBox(height: AppSpacing.sm),
                  _planCard(context, 'Titan Plus', 899, 100000, false),
                  const SizedBox(height: AppSpacing.sm),
                  _planCard(context, 'Pro Launch', 1499, 200000, false),
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
              child: const Text('MOST POPULAR', style: TextStyle(color: AppColors.pureWhite, fontSize: 10)),
            ),
          if (popular) const SizedBox(height: AppSpacing.sm),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.xs),
          Text('₹$cash demo cash', style: const TextStyle(color: AppColors.ink4)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹$price', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              ElevatedButton(
                onPressed: () async {
                  final auth = context.read<AuthService>();
                  await SupabaseService().creditDemoCash(cash.toDouble());
                  await auth.refreshUser();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('₹$cash demo cash credited to your wallet')));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold),
                child: const Text('Top up', style: TextStyle(color: AppColors.pureWhite)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
