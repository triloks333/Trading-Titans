import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

/// A one-time, consumable top-up product. These map 1:1 to Google Play
/// **in-app products** (one-time purchases, NOT subscriptions). [productId]
/// must match the product ID created in the Play Console.
///
/// NOTE: the Play Billing paywall is not wired yet — tapping "Top up" still
/// shows the beta-phase dialog. The product definitions below are ready so
/// that hooking up `in_app_purchase` later only needs to read this list.
class TopUpProduct {
  final String productId; // Play Console one-time product ID
  final String title;
  final int price; // INR
  final int cash; // demo cash credited
  final bool popular;

  const TopUpProduct({
    required this.productId,
    required this.title,
    required this.price,
    required this.cash,
    this.popular = false,
  });
}

const List<TopUpProduct> kTopUpProducts = [
  TopUpProduct(
    productId: 'topup_starter_199',
    title: 'Starter Boost',
    price: 199,
    cash: 100000,
    popular: true,
  ),
  TopUpProduct(
    productId: 'topup_titan_599',
    title: 'Titan Plus',
    price: 599,
    cash: 500000,
  ),
  TopUpProduct(
    productId: 'topup_pro_999',
    title: 'Pro Launch',
    price: 999,
    cash: 1000000,
  ),
];

/// Pre-registration reward — a FREE one-time product (price ₹0) granted by
/// Google Play to users who pre-registered for the app. It is NOT sold and is
/// intentionally excluded from [kTopUpProducts] (the purchasable list).
///
/// Setup: in the Play Console, create an in-app product with this exact ID and
/// price 0, then attach it as the reward on the Pre-registration campaign.
/// Delivery (when Play Billing is wired): on first launch, Play reports the
/// pre-reg entitlement as an owned purchase of this product — the app verifies
/// it server-side, credits [cash] demo cash once, then acknowledges/consumes it.
/// Amount below is adjustable.
const TopUpProduct kPreRegistrationGift = TopUpProduct(
  productId: 'prereg_gift',
  title: 'Pre-registration Gift',
  price: 0,
  cash: 50000,
);

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
            Text('₹${wallet.toStringAsFixed(0)}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.lg),
            Text('One-time top-up products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text('A single purchase — credited once, not a subscription.',
                style: TextStyle(fontSize: 12, color: AppColors.ink4)),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView(
                children: [
                  for (final p in kTopUpProducts) ...[
                    _productCard(context, p),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productCard(BuildContext context, TopUpProduct product) {
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
          if (product.popular)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(color: AppColors.imperialGold, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Text('MOST POPULAR', style: TextStyle(color: AppColors.pureWhite, fontSize: 10)),
            ),
          if (product.popular) const SizedBox(height: AppSpacing.sm),
          Text(product.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: AppSpacing.xs),
          Text('₹${product.cash} demo cash', style: TextStyle(color: AppColors.ink4)),
          const SizedBox(height: 2),
          Text('One-time purchase', style: TextStyle(fontSize: 11, color: AppColors.ink5, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('₹${product.price}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              ElevatedButton(
                onPressed: () {
                  // Paywall not wired yet — keep the beta-phase notice.
                  _showBetaPhaseDialog(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.imperialGold),
                child: Text('Top up', style: TextStyle(color: AppColors.pureWhite)),
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
