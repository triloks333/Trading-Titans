import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
                  _showGooglePlayPaywall(context, title, price, cash);
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

  void _showGooglePlayPaywall(BuildContext context, String title, int price, int cash) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return _GooglePlayPaywallSheet(
          title: title,
          price: price,
          cash: cash,
          parentContext: context,
        );
      },
    );
  }
}

class _GooglePlayPaywallSheet extends StatefulWidget {
  final String title;
  final int price;
  final int cash;
  final BuildContext parentContext;

  const _GooglePlayPaywallSheet({
    required this.title,
    required this.price,
    required this.cash,
    required this.parentContext,
  });

  @override
  State<_GooglePlayPaywallSheet> createState() => _GooglePlayPaywallSheetState();
}

class _GooglePlayPaywallSheetState extends State<_GooglePlayPaywallSheet> {
  bool _purchasing = false;
  bool _success = false;

  Future<void> _handleBuy() async {
    final auth = widget.parentContext.read<AuthService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(widget.parentContext);

    setState(() => _purchasing = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _purchasing = false;
      _success = true;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    try {
      await SupabaseService().purchasePackage(widget.title, widget.price.toDouble(), widget.cash.toDouble());
      await auth.refreshUser();
      if (mounted) {
        navigator.pop(); // Close play store sheet
        messenger.showSnackBar(
          SnackBar(
            content: Text('₹${widget.cash} demo cash successfully credited!'),
            backgroundColor: AppColors.bull,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Purchase verification failed: $e'),
            backgroundColor: AppColors.bear,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.parentContext.read<AuthService>();
    final email = auth.user?.email ?? 'trader@tradingtitans.com';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Google Play header
            Row(
              children: [
                const Icon(Icons.play_arrow, color: Color(0xFF0F9D58), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Google Play',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: const Color(0xFF5F6368),
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFFDADCE0)),
            if (_success) ...[
              const SizedBox(height: 32),
              const Center(
                child: Icon(Icons.check_circle, color: Color(0xFF0F9D58), size: 64),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Payment Successful',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ] else if (_purchasing) ...[
              const SizedBox(height: 32),
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF0F9D58),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Processing transaction...',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: AppColors.ink3,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ] else ...[
              // Product details
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          'Trading Titans (Consumable)',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.ink4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${widget.price.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // User account
              Row(
                children: [
                  const Icon(Icons.account_circle, color: Color(0xFF5F6368), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    email,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF5F6368),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Payment method row
              Row(
                children: [
                  const Icon(Icons.payment, color: Color(0xFF0F9D58), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Google Pay (Visa •••• 4111)',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 18, color: Color(0xFF5F6368)),
                ],
              ),
              const SizedBox(height: 24),
              // Buy button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _handleBuy,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F9D58),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    '1-TAP BUY',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

