import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/app_constants.dart';
import '../../models/order.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/skeleton.dart';
import '../../services/nav_tab_service.dart';
import 'subscribe_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      _orders = await SupabaseService().getOrders();
      await auth.refreshUser();
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final wallet = auth.user?.walletBalance ?? 0.0;
    final active = auth.user?.subscriptionActive ?? false;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          child: _loading
              ? const ListSkeleton()
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text('Wallet', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: AppCard.primary,
                      child: Column(
                        children: [
                          Text('DEMO CASH BALANCE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink4, letterSpacing: 0.5)),
                          const SizedBox(height: AppSpacing.sm),
                          Text('₹${wallet.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                            decoration: AppCard.badge(active ? AppColors.bullLight : AppColors.cream),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(active ? Icons.check_circle : Icons.info_outline, size: 14, color: active ? AppColors.bull : AppColors.ink4),
                                const SizedBox(width: 4),
                                Text(active ? 'Active · Trading enabled' : 'Free Starter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: active ? AppColors.bull : AppColors.ink4)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GestureDetector(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscribeScreen()));
                        _loadOrders();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: AppCard.darkCta,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Top-up Demo Cash', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 2),
                                  Text('From ₹199 · Up to ₹10,00,000', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFBBD7F8))),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_circle_right, size: 28, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Transaction History', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.sm),
                    if (_orders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.goldPale,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.receipt_long_rounded, size: 34, color: AppColors.imperialGold),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text('No transactions yet', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                              const SizedBox(height: 4),
                              Text('Your buys and sells will show up here', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
                              const SizedBox(height: AppSpacing.md),
                              ElevatedButton(
                                onPressed: () => NavTabService.goToTab(NavTabService.trade),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.imperialGold,
                                  foregroundColor: AppColors.pureWhite,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                                ),
                                child: Text('Place your first order', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._orders.map((order) => _buildTransactionRow(order)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildTransactionRow(Order order) {
    final isBuy = order.side == 'buy';
    // Futures move only margin (~15% of notional), not the full contract value,
    // so the wallet history shows the margin actually charged — keeping it
    // consistent with the wallet balance and the portfolio's deployed capital.
    final bool isFuture = order.instrumentType == 'FUTURE';
    final double displayAmount =
        isFuture ? order.total * AppConstants.fnoMarginPct : order.total;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.secondary,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: AppCard.badge(isBuy ? AppColors.bullLight : AppColors.bearLight),
            child: Text(
              order.side.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isBuy ? AppColors.bull : AppColors.bear, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.symbol, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text('${order.quantity.toStringAsFixed(order.market == 'crypto' ? 4 : 0)} @ ₹${order.price.toStringAsFixed(2)}', style: GoogleFonts.inter(color: AppColors.ink4)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${displayAmount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(order.createdAt != null ? '${order.createdAt!.day}/${order.createdAt!.month}/${order.createdAt!.year}' : '-', style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4)),
            ],
          ),
        ],
      ),
    );
  }
}
