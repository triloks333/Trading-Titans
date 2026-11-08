import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/portfolio.dart';
import '../../models/position_model.dart';
import '../../services/app_flags_service.dart';
import '../../services/auth_service.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/skeleton.dart';
import 'challenges_screen.dart';
import 'orders_screen.dart';
import 'refer_earn_screen.dart';
import 'subscribe_screen.dart';
import '../../services/churn_telemetry_service.dart';

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

/// Credited to both sides of a referral by handle_new_user (see
/// 20261024010000_allow_pkr_eur_and_new_markets_and_guest_cash.sql).
const double kReferralReward = 500;

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _txns = [];
  double _invested = 0, _blocked = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    try {
      // The wallet's own statement, not the order list. getWalletTransactions()
      // returns [] rather than throwing, so the tab renders even without the ledger.
      final svc = SupabaseService();
      final results = await Future.wait<Object>([
        svc.getWalletTransactions(),
        svc.getHoldings().catchError((_) => <Holding>[]),
        svc.getFoPositions().catchError((_) => <FoPosition>[]),
      ]);
      _txns = results[0] as List<Map<String, dynamic>>;
      _invested = (results[1] as List<Holding>).where((h) => h.quantity > 0 && h.isEquity).fold(0.0, (s, h) => s + h.invested);
      _blocked = (results[2] as List<FoPosition>).fold(0.0, (s, p) => s + p.marginBlocked) +
          (results[1] as List<Holding>).where((h) => h.quantity < 0).fold(0.0, (s, h) => s + h.invested.abs());
      await auth.refreshUser();
    } catch (e) {
      // A server hiccup keeps what is on screen; the balance comes from the last-known user.
      debugPrint('WalletScreen._load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The opening credit from the ledger; ₹1,100 (the signup grant) if it is not there.
  double get _starting {
    final opening = _txns.where((t) => t['kind'] == 'opening').firstOrNull;
    return (opening?['amount'] as num?)?.toDouble() ?? 1100;
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<AuthService>().user?.walletBalance ?? 0.0;
    // The derived tier, not profiles.subscription_active (defaulted true at signup).
    final plan = context.watch<PlanService>();
    // Paid surfaces stay hidden unless the backend flag turns them on.
    final monetized = context.watch<AppFlagsService>().monetizationEnabled;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              Expanded(child: Text('Wallet', style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: AppColors.ink))),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const ListSkeleton()
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      children: [
                        _balanceCard(wallet, plan, monetized),
                        _heading('Earn more demo cash'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          child: Row(children: [
                            _earnCard(Icons.track_changes_rounded, AppColors.titanGold, AppColors.titanGoldSoft, 'Challenges',
                                'Demo cash for every win', const ChallengesScreen(), 'wallet_earn_cash_challenges_row'),
                            const SizedBox(width: 8),
                            _earnCard(Icons.person_add_alt_1_outlined, AppColors.goldMid, AppColors.goldPale, 'Refer a friend',
                                '${Money.wallet(kReferralReward, decimals: 0)} per signup', const ReferEarnScreen(), 'wallet_earn_cash_refer_friend_row'),
                          ]),
                        ),
                        if (monetized) _vipCard(),
                        _heading('Transaction history'),
                        Divider(color: AppColors.birch),
                        if (_txns.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(children: [
                              Icon(Icons.receipt_long_rounded, size: 36, color: AppColors.ink4),
                              const SizedBox(height: AppSpacing.md),
                              Text('No wallet activity yet', style: AppText.bodyBold),
                              const SizedBox(height: 4),
                              Text('Rewards, referral bonuses and the cash impact of your trades will appear here.',
                                  textAlign: TextAlign.center, style: AppText.bodySmall),
                            ]),
                          )
                        else
                          ..._txns.map(_buildLedgerRow),
                      ],
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 22, AppSpacing.lg, 8),
        child: Text(text.toUpperCase(), style: AppText.sectionLabel),
      );

  Widget _balanceCard(double wallet, PlanService plan, bool monetized) {
    Widget stat(String label, String value, {bool end = false}) => Expanded(
          child: Column(crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Text(label, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
            Text(value, style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 4, AppSpacing.lg, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('DEMO CASH BALANCE', style: AppText.sectionLabel)),
          if (monetized)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: AppCard.badge(plan.isPaid ? AppColors.titanGoldSoft : AppColors.cream),
              child: Text(plan.isPaid ? plan.tier.toUpperCase() : 'FREE',
                  style: AppText.badge.copyWith(color: plan.isPaid ? AppColors.titanGold : AppColors.ink3)),
            ),
        ]),
        const SizedBox(height: 4),
        // Follows the display currency; the stored balance is always INR.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(Money.wallet(wallet), style: AppFonts.mono(size: 34, weight: FontWeight.w600, color: AppColors.ink, spacing: -0.5)),
        ),
        Text('Virtual money for practice. Not withdrawable.', style: AppFonts.sans(size: 12, color: AppColors.ink4)),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.birch))),
          child: Row(children: [
            stat('Invested', Money.wallet(_invested, decimals: 2)),
            stat('Blocked', Money.wallet(_blocked, decimals: 2)),
            stat('Starting', Money.wallet(_starting, decimals: 0), end: true),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          if (monetized) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  ChurnTelemetryService.instance.recordButtonTap('wallet_balance_card_upgrade_or_topup_cta');
                  _push(const SubscribeScreen(initialTabIndex: 1));
                },
                child: const Text('Top up'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream),
              onPressed: () => _push(const OrdersScreen()),
              child: const Text('Order history'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _earnCard(IconData icon, Color fg, Color bg, String title, String sub, Widget screen, String tapId) => Expanded(
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              ChurnTelemetryService.instance.recordButtonTap(tapId);
              _push(screen);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Icon(icon, size: 20, color: fg),
                ),
                const SizedBox(height: 8),
                Text(title, style: AppText.bodyBold),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
              ]),
            ),
          ),
        ),
      );

  /// Plans and mentorship, only while paid plans are switched on.
  Widget _vipCard() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 8, AppSpacing.lg, 0),
        child: Material(
          color: AppColors.titanGoldSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.titanGold)),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _push(const SubscribeScreen(initialTabIndex: 0)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.workspace_premium_rounded, size: 26, color: AppColors.titanGold),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('VIP mentorship & plans', style: AppText.bodyBold),
                    Text('Twice-weekly live 1-on-1 sessions & options unlock', style: AppFonts.sans(size: 12, color: AppColors.ink3)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
              ]),
            ),
          ),
        ),
      );

  /// One statement line: icon, label, date, signed amount and running balance.
  Widget _buildLedgerRow(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (tx['balance_after'] as num?)?.toDouble();
    final created = DateTime.tryParse(tx['created_at'] as String? ?? '')?.toLocal();
    final display = walletTxDisplay(kind: tx['kind'] as String? ?? '', amount: amount, description: tx['description'] as String?);
    final now = DateTime.now();
    String when() {
      if (created == null) return '';
      final days = DateTime(now.year, now.month, now.day).difference(DateTime(created.year, created.month, created.day)).inDays;
      final d = days == 0 ? 'Today' : days == 1 ? 'Yesterday' : DateFormat('d MMM').format(created);
      return tx['kind'] == 'trade' ? '$d · order' : d;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Icon(display.icon, size: 18, color: AppColors.ink3),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(display.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 14, weight: FontWeight.w500, color: AppColors.ink)),
            Text(when(), style: AppFonts.sans(size: 12, color: AppColors.ink4)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          // Ledger amounts are INR. Credits are green; debits stay neutral, as in the design.
          Text(Money.signedWallet(amount, decimals: 2),
              style: AppFonts.mono(size: 14, weight: FontWeight.w500, color: display.isCredit ? AppColors.bull : AppColors.ink)),
          if (balanceAfter != null)
            Text('Bal ${Money.wallet(balanceAfter)}', style: AppFonts.mono(size: 11, color: AppColors.ink4)),
        ]),
      ]),
    );
  }
}
