import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/quote.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/auth_kit.dart';

/// What the guided first trade buys.
typedef FirstTradePick = ({String symbol, String name, String market, double? spend});

/// NSE stock when NSE is open and the user picked Indian stocks, otherwise
/// Bitcoin, which always fills, so the first trade never just sits pending.
/// A crypto pick spends a fixed rupee amount (fractional quantity); a stock
/// buys one share, so it must be cheap enough for the ₹500 guest balance.
FirstTradePick pickFirstTrade(List<String> markets, {DateTime? at}) {
  if (markets.contains(MarketHours.stock) && MarketHours.isOpen(MarketHours.stock, at: at)) {
    return (symbol: 'TATASTEEL', name: 'Tata Steel', market: MarketHours.stock, spend: null);
  }
  return (symbol: 'BTC', name: 'Bitcoin', market: MarketHours.crypto, spend: 200);
}

/// Quantity for [pick] at [price]: one share, or the crypto spend rounded down
/// to 6 decimals so the cost never exceeds the stated amount.
double firstTradeQuantity(FirstTradePick pick, double price) {
  final spend = pick.spend;
  if (spend == null || price <= 0) return 1;
  return (spend / price * 1e6).floorToDouble() / 1e6;
}

/// Onboarding's last two screens: a pre-filled first trade, then the "you own
/// it" screen with live P&L and the alerts ask. [onFinish] fires when the user
/// is done, whether they traded or skipped.
class FirstTradeFlow extends StatefulWidget {
  const FirstTradeFlow({super.key, required this.markets, required this.onFinish});

  final List<String> markets;

  /// `traded` is false when the user skipped the trade.
  final void Function({required bool traded}) onFinish;

  @override
  State<FirstTradeFlow> createState() => _FirstTradeFlowState();
}

class _FirstTradeFlowState extends State<FirstTradeFlow> {
  late final FirstTradePick _pick = pickFirstTrade(widget.markets);
  Quote? _quote;
  bool _loading = true;
  bool _placing = false;
  String? _error;
  Order? _order;
  double? _livePrice;
  Timer? _poll;
  bool _alertsOn = false;
  bool _alertsBusy = false;

  @override
  void initState() {
    super.initState();
    ChurnTelemetryService.instance.recordHomeScreen('onboarding_first_trade');
    _loadQuote();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = await SupabaseService().getQuote(_pick.symbol, _pick.market);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _loading = false;
        if (q == null || q.price <= 0) _error = 'Couldn’t load the live price. Check your connection.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Couldn’t load the live price. Check your connection.';
        });
      }
    }
  }

  double get _qty => firstTradeQuantity(_pick, _quote?.price ?? 0);

  Future<void> _buy() async {
    final q = _quote;
    if (q == null) return;
    setState(() {
      _placing = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    try {
      final order = await SupabaseService().placeOrder(
        symbol: q.symbol,
        market: q.market,
        side: 'buy',
        quantity: _qty,
        isMarket: true,
      );
      ChurnTelemetryService.instance.recordTradePlaced(symbol: q.symbol, side: 'buy', qty: _qty, segment: 'EQUITY');
      unawaited(AnalyticsService.logFirstTradeOnce(q.market));
      unawaited(AnalyticsService.log('onboarding_first_trade', {'symbol': q.symbol, 'executed': order.isExecuted ? 1 : 0}));
      unawaited(SupabaseService().evaluateChallenges());
      unawaited(auth.refreshUser());
      if (!mounted) return;
      setState(() {
        _order = order;
        _livePrice = q.price;
      });
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPrice());
    } catch (e) {
      ChurnTelemetryService.instance.recordActionError('order_failed');
      if (mounted) setState(() => _error = e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), ''));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _refreshPrice() async {
    try {
      final q = await SupabaseService().getQuote(_pick.symbol, _pick.market);
      if (mounted && q != null && q.price > 0) setState(() => _livePrice = q.price);
    } catch (_) {}
  }

  Future<void> _turnOnAlerts() async {
    final order = _order;
    final ref = order?.price ?? _livePrice;
    setState(() => _alertsBusy = true);
    try {
      await NotificationService.instance.setup();
      if (ref != null && ref > 0) {
        final svc = SupabaseService();
        for (final (dir, mult) in const [('above', 1.02), ('below', 0.98)]) {
          await svc.createPriceAlert(
            symbol: _pick.symbol,
            market: _pick.market,
            name: _pick.name,
            targetPrice: ref * mult,
            direction: dir,
            referencePrice: ref,
          );
        }
      }
      unawaited(AnalyticsService.log('onboarding_alerts_on'));
      if (mounted) setState(() => _alertsOn = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Couldn’t set the alerts. You can add them from the chart.')));
      }
    } finally {
      if (mounted) setState(() => _alertsBusy = false);
    }
  }

  void _skip() {
    unawaited(AnalyticsService.log('onboarding_first_trade_skipped'));
    widget.onFinish(traded: false);
  }

  @override
  Widget build(BuildContext context) => _order == null ? _tradeView() : _winView(_order!);

  // ── Screen 1: the pre-filled trade ─────────────────────────────────────────

  Widget _tradeView() {
    final q = _quote;
    final balance = context.watch<AuthService>().user?.walletBalance;
    final cost = q == null ? null : q.price * _qty;
    final isCrypto = _pick.market == MarketHours.crypto;
    final title = isCrypto ? 'Buy ₹${_pick.spend!.toStringAsFixed(0)} of ${_pick.name}' : 'Buy 1 share of ${_pick.name}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, 0), children: [
          Text('YOUR FIRST TRADE', style: AppText.sectionLabel.copyWith(color: AppColors.titanGold)),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: AppFonts.sans(size: 26, weight: FontWeight.w700, color: AppColors.ink, height: 1.15)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isCrypto && !MarketHours.isOpen(MarketHours.stock)
                ? 'Indian markets are closed right now, so we picked crypto — it trades 24/7. Tap Buy and watch your P&L move live.'
                : 'We filled it in for you. Tap Buy and watch your P&L move live.',
            style: AppFonts.sans(size: 15, color: AppColors.ink3, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Center(child: CircularProgressIndicator()))
          else if (q != null && q.price > 0) ...[
            _card(Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.symbol, style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
                  Text(isCrypto ? 'Crypto' : 'NSE · Equity', style: AppText.bodySmall),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(Money.instrument(q.price, market: q.market),
                    style: AppFonts.mono(size: 18, weight: FontWeight.w600, color: AppColors.ink)),
                Text('${q.changePct >= 0 ? '+' : ''}${q.changePct.toStringAsFixed(2)}% today',
                    style: AppFonts.mono(size: 12, color: q.changePct >= 0 ? AppColors.bull : AppColors.bear)),
              ]),
            ])),
            const SizedBox(height: AppSpacing.md),
            _card(Column(children: [
              _row('Quantity', isCrypto ? _qty.toStringAsFixed(6) : '1'),
              const SizedBox(height: AppSpacing.md),
              _row('Order type', 'Market'),
              if (balance != null && cost != null) ...[
                const SizedBox(height: AppSpacing.md),
                Divider(height: 1, color: AppColors.birch),
                const SizedBox(height: AppSpacing.md),
                _row('Demo cash left after', Money.wallet(balance - cost, decimals: 2)),
              ],
            ])),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.titanGold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                      'A market order buys right now at the live price. It’s demo cash — you can’t lose real money.',
                      style: AppFonts.sans(size: 13, color: AppColors.ink2, height: 1.45)),
                ),
              ]),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: AppSpacing.md), AuthError(_error!)],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, AppSpacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (q != null && q.price > 0)
            AuthPrimaryButton(
              label: isCrypto ? 'Buy · ${Money.wallet(cost ?? 0, decimals: 0)}' : 'Buy 1 share · ${Money.instrument(q.price, market: q.market)}',
              busy: _placing,
              onPressed: _placing ? null : _buy,
            )
          else if (!_loading)
            AuthPrimaryButton(label: 'Try again', onPressed: _loadQuote),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _placing ? null : _skip,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Pick my own'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: _placing ? null : _skip,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: AppColors.ink3),
                child: const Text('Skip for now'),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }

  // ── Screen 2: you own it ───────────────────────────────────────────────────

  Widget _winView(Order order) {
    final filled = order.isExecuted;
    final live = _livePrice ?? order.price;
    final pnl = (live - order.price) * order.quantity;
    final what = _pick.market == MarketHours.crypto ? 'some ${_pick.name}' : '1 share of ${_pick.name}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, AppSpacing.xl, 20, 0), children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.bull.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(filled ? Icons.check_rounded : Icons.schedule_rounded, size: 36, color: AppColors.bull),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(filled ? 'You own $what' : 'Order placed',
              textAlign: TextAlign.center,
              style: AppFonts.sans(size: 28, weight: FontWeight.w700, color: AppColors.ink, height: 1.15)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            filled ? 'That’s your first trade. Your P&L updates with every tick.' : 'It fills as soon as the market opens.',
            textAlign: TextAlign.center,
            style: AppFonts.sans(size: 15, color: AppColors.ink3, height: 1.45),
          ),
          if (filled) ...[
            const SizedBox(height: AppSpacing.lg),
            _card(Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Live P&L', style: AppText.bodySmall),
                  Text(Money.wallet(pnl, decimals: 2),
                      style: AppFonts.mono(size: 22, weight: FontWeight.w600, color: pnl >= 0 ? AppColors.bull : AppColors.bear)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Bought at', style: AppText.bodySmall),
                Text(Money.instrument(order.price, market: order.market),
                    style: AppFonts.mono(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
              ]),
            ])),
          ],
          const SizedBox(height: AppSpacing.lg),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.notifications_active_outlined, color: AppColors.blue),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Know when ${_pick.name} moves',
                      style: AppFonts.sans(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text('We’ll ping you if it moves 2% either way, and when your orders fill.',
                      style: AppFonts.sans(size: 13, color: AppColors.ink3, height: 1.45)),
                ]),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            _alertsOn
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.check_circle_rounded, size: 18, color: AppColors.bull),
                    const SizedBox(width: AppSpacing.xs),
                    Text('Alerts on', style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.bull)),
                  ])
                : OutlinedButton(
                    onPressed: _alertsBusy ? null : _turnOnAlerts,
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(_alertsBusy ? 'Turning on…' : 'Turn on alerts'),
                  ),
          ])),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, AppSpacing.lg),
        child: AuthPrimaryButton(label: 'Go to my portfolio', onPressed: () => widget.onFinish(traded: true)),
      ),
    ]);
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.birch),
        ),
        child: child,
      );

  Widget _row(String label, String value) => Row(children: [
        Expanded(child: Text(label, style: AppFonts.sans(size: 14, color: AppColors.ink3))),
        Text(value, style: AppFonts.mono(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
      ]);
}
