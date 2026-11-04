import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/skeleton.dart';
import '../../services/app_flags_service.dart';
import '../../services/plan_service.dart';
import 'subscribe_screen.dart';
import 'challenges_screen.dart';
import 'orders_screen.dart';
import 'package:google_fonts/google_fonts.dart';

/// How one `wallet_transactions` row is presented.
class WalletTxDisplay {
  final String label;
  final IconData icon;

  /// True when the row added money to the wallet. Drives the sign colour, so
  /// getting it wrong misreports a debit as a credit.
  final bool isCredit;

  const WalletTxDisplay({
    required this.label,
    required this.icon,
    required this.isCredit,
  });
}

/// Maps a ledger row to its label and icon.
///
/// Kept pure and top-level so the money-facing question — does this read as a
/// credit or a debit? — is testable without a database or a widget tree.
///
/// [kind] comes straight from the database and may be a value this build has
/// never seen: the ledger column deliberately has no CHECK constraint, so that
/// no statement line is ever dropped for carrying an unrecognised label. An
/// unknown kind therefore has to render sensibly rather than throw, falling back
/// to the row's own [description] and the sign of [amount], both of which are
/// always meaningful.
WalletTxDisplay walletTxDisplay({
  required String kind,
  required double amount,
  String? description,
}) {
  final credit = amount >= 0;
  // An empty description from the database is as good as absent.
  final desc = (description != null && description.trim().isNotEmpty)
      ? description
      : null;

  switch (kind) {
    case 'opening':
      return WalletTxDisplay(
        label: desc ?? 'Opening balance',
        icon: Icons.flag_rounded,
        isCredit: credit,
      );
    case 'trade':
      return WalletTxDisplay(
        label: desc ?? (credit ? 'Trade proceeds' : 'Trade cost'),
        icon: Icons.candlestick_chart_rounded,
        isCredit: credit,
      );
    case 'referral':
      return WalletTxDisplay(
        label: desc ?? 'Referral bonus',
        icon: Icons.group_add_rounded,
        isCredit: credit,
      );
    case 'plan':
      return WalletTxDisplay(
        label: desc ?? 'Plan credit',
        icon: Icons.workspace_premium_rounded,
        isCredit: credit,
      );
    case 'credit':
      return WalletTxDisplay(
        label: desc ?? 'Demo cash credited',
        icon: Icons.card_giftcard_rounded,
        isCredit: credit,
      );
    // Written by convert_guest_account() via the app.wallet_reason hint, which
    // leaves description NULL, so the fallback label is what actually shows.
    case 'conversion_bonus':
      return WalletTxDisplay(
        label: desc ?? 'Permanent account bonus',
        icon: Icons.lock_open_rounded,
        isCredit: credit,
      );
    default:
      return WalletTxDisplay(
        label: desc ?? (credit ? 'Credit' : 'Debit'),
        icon: Icons.receipt_long_rounded,
        isCredit: credit,
      );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _txns = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    try {
      // The wallet's OWN statement. This used to call getOrders(), which showed
      // the order list under a "Transaction History" heading — duplicating the
      // Orders screen while still omitting every non-trade movement.
      // getWalletTransactions() returns [] instead of throwing, so a build that
      // ships before the ledger migration is applied still renders this tab.
      _txns = await SupabaseService().getWalletTransactions();
      await auth.refreshUser();
    } catch (e) {
      // refreshUser can still fail on a server hiccup, and this used to be
      // try/finally with no catch — a Supabase 504 escaped as an unhandled async
      // error and was reported as a fatal crash. Keep what is on screen; the
      // balance renders from AuthService's last-known user.
      debugPrint('WalletScreen._load failed: $e');
    } finally {
      // Guarded: the original could setState after the tab was disposed.
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final wallet = auth.user?.walletBalance ?? 0.0;
    // The derived tier, not `profiles.subscription_active` — that column is
    // defaulted true at signup and no payment path writes it, so it reported
    // every free account as "Active · Trading enabled".
    final plan = context.watch<PlanService>();
    final active = plan.isPaid;
    // Paid surfaces are hidden unless the backend flag says otherwise, so the
    // app reads as completely free by default.
    final monetized = context.watch<AppFlagsService>().monetizationEnabled;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const ListSkeleton()
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text('Wallet', style: GoogleFonts.ibmPlexSans(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: AppCard.primary,
                      child: Column(
                        children: [
                          Text('DEMO CASH BALANCE', style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink4, letterSpacing: 0.5)),
                          const SizedBox(height: AppSpacing.sm),
                          // Follows the user's display currency. The stored
                          // balance is always INR, hence the INR source.
                          Text(Money.wallet(wallet), style: GoogleFonts.ibmPlexSans(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.ink, letterSpacing: -0.5)),
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                            decoration: AppCard.badge(monetized && active ? AppColors.bullLight : AppColors.cream),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(monetized && active ? Icons.check_circle : Icons.info_outline,
                                    size: 14,
                                    color: monetized && active ? AppColors.bull : AppColors.ink4),
                                const SizedBox(width: 4),
                                Text(
                                  monetized
                                      ? (active
                                          ? '${plan.tier.toUpperCase()} · Trading enabled'
                                          : 'Free plan')
                                      : 'Free for everyone',
                                  style: GoogleFonts.ibmPlexSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: monetized && active ? AppColors.bull : AppColors.ink4),
                                ),
                              ],
                            ),
                          ),
                          if (monetized) ...[
                            const SizedBox(height: AppSpacing.lg),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SubscribeScreen(initialTabIndex: 1),
                                    ),
                                  );
                                  _load();
                                },
                                icon: const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                                label: Text(
                                  'Top Up Demo Capital',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.imperialGold,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Earning demo cash through challenges is the only top-up
                    // route while monetization is off.
                    GestureDetector(
                      onTap: () async {
                        await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ChallengesScreen()));
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: AppCard.darkCta,
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events_rounded, size: 26, color: Colors.white),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Earn more demo cash',
                                      style: GoogleFonts.ibmPlexSans(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                  const SizedBox(height: 2),
                                  Text('Complete challenges for rewards',
                                      style: GoogleFonts.ibmPlexSans(
                                          fontSize: 13, color: const Color(0xFFBBD7F8))),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_circle_right, size: 28, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                    if (monetized) ...[
                      const SizedBox(height: AppSpacing.md),
                      GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SubscribeScreen(initialTabIndex: 0),
                            ),
                          );
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4338CA).withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.workspace_premium_rounded, size: 22, color: Color(0xFFFFD700)),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'VIP Mentorship & Plans',
                                          style: GoogleFonts.ibmPlexSans(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '₹1L+/MO',
                                            style: GoogleFonts.ibmPlexSans(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFFFFD700),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Twice-weekly live 1-on-1 sessions & options unlock',
                                      style: GoogleFonts.ibmPlexSans(
                                        fontSize: 12,
                                        color: const Color(0xFFC7D2FE),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_circle_right, size: 28, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Transaction History', style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                        ),
                        // Trades appear below as their cash impact only. The full
                        // order detail lives on its own screen — which this tab
                        // used to duplicate wholesale — so keep it one tap away.
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const OrdersScreen())),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.imperialGold,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text('Order history', style: GoogleFonts.ibmPlexSans(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_txns.isEmpty)
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
                              Text('No wallet activity yet', style: GoogleFonts.ibmPlexSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                              const SizedBox(height: 4),
                              Text(
                                'Rewards, referral bonuses and the cash impact of your trades will appear here.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink4),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._txns.map(_buildLedgerRow),
                  ],
                ),
        ),
      ),
    );
  }

  /// One line of the wallet statement.
  ///
  /// Every figure here is a real rupee movement read back from the ledger, so
  /// unlike the old order-derived row there is no margin percentage to re-derive
  /// and no pending-order currency special case — the database already recorded
  /// exactly what left or entered the wallet.
  Widget _buildLedgerRow(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (tx['balance_after'] as num?)?.toDouble();
    final created = DateTime.tryParse(tx['created_at'] as String? ?? '')?.toLocal();

    final display = walletTxDisplay(
      kind: tx['kind'] as String? ?? '',
      amount: amount,
      description: tx['description'] as String?,
    );
    final color = display.isCredit ? AppColors.bull : AppColors.bear;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.secondary,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(display.icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(display.label, style: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  created != null ? '${created.day}/${created.month}/${created.year}' : '-',
                  style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Ledger amounts are stored in INR, so the wallet source is right.
              Text(
                Money.signedWallet(amount, decimals: 2),
                style: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.w700, color: color),
              ),
              if (balanceAfter != null) ...[
                const SizedBox(height: 2),
                // The running balance is what lets a user reconcile the list
                // against the figure at the top of the screen.
                Text('Bal ${Money.wallet(balanceAfter)}', style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
