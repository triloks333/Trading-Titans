import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency.dart';
import '../../core/money.dart';
import '../../core/option_pricing.dart';
import '../../core/strategy.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/upgrade_sheet.dart';

/// Multi-leg options strategy builder (Titan).
///
/// Anyone can build a strategy and see its payoff, Greeks and what-if P&L, so a
/// free user feels what Titan does. Placing the legs as one basket is Titan-only.
/// Every number is an estimate from [OptionPricing], the app's single pricing model.
class StrategyBuilderScreen extends StatefulWidget {
  const StrategyBuilderScreen({
    super.key,
    required this.underlying,
    required this.spot,
    required this.expiry,
    required this.lotSize,
    required this.chain,
    this.market = 'stock',
  });

  final String underlying;
  final double spot;
  final String expiry;
  final int lotSize;

  /// Option chain rows for [expiry]: `{strike_price, call: {...}, put: {...}}`.
  final List<Map<String, dynamic>> chain;
  final String market;

  @override
  State<StrategyBuilderScreen> createState() => _StrategyBuilderScreenState();
}

class _StrategyBuilderScreenState extends State<StrategyBuilderScreen> {
  late final List<double> _strikes;
  final List<StrategyLeg> _legs = [];
  StrategyPreset? _preset;
  double _movePct = 0;
  double _daysPassed = 0;
  bool _placing = false;

  double get _dte => daysToExpiry(widget.expiry);
  Currency get _src => Money.sourceFor(widget.market);

  @override
  void initState() {
    super.initState();
    _strikes = [
      for (final r in widget.chain) (r['strike_price'] as num).toDouble(),
    ]..sort();
    _apply(StrategyPreset.longStraddle);
  }

  Map<String, dynamic>? _row(double strike) => widget.chain
      .where((r) => (r['strike_price'] as num).toDouble() == strike)
      .firstOrNull;

  Map<String, dynamic>? _contract(String type, double strike) {
    final r = _row(strike);
    final c = r?[type == 'CE' ? 'call' : 'put'];
    return c is Map ? Map<String, dynamic>.from(c) : null;
  }

  double _premium(String type, double strike) {
    final p = (_contract(type, strike)?['price'] as num?)?.toDouble();
    if (p != null && p > 0) return p;
    return OptionPricing.optionPremium(
      optionType: type,
      spot: widget.spot,
      strike: strike,
      daysToExpiry: _dte,
      symbol: widget.underlying,
    );
  }

  String? _symbol(String type, double strike) =>
      _contract(type, strike)?['symbol'] as String?;

  void _apply(StrategyPreset p) {
    setState(() {
      _preset = p;
      _legs
        ..clear()
        ..addAll(p.build(_strikes, widget.spot, _premium, _symbol));
    });
  }

  void _repriceLeg(StrategyLeg l) {
    l.premium = _premium(l.type, l.strike);
    l.symbol = _symbol(l.type, l.strike);
  }

  void _stepStrike(StrategyLeg l, int dir) {
    final i = _strikes.indexOf(l.strike);
    final next = (i < 0 ? 0 : i + dir).clamp(0, _strikes.length - 1);
    setState(() {
      l.strike = _strikes[next];
      _repriceLeg(l);
      _preset = null;
    });
  }

  void _addLeg() {
    if (_strikes.isEmpty) return;
    var atm = _strikes.first;
    for (final k in _strikes) {
      if ((k - widget.spot).abs() < (atm - widget.spot).abs()) atm = k;
    }
    setState(() {
      _legs.add(
        StrategyLeg(
          buy: true,
          type: 'CE',
          strike: atm,
          premium: _premium('CE', atm),
          symbol: _symbol('CE', atm),
        ),
      );
      _preset = null;
    });
  }

  String _money(double v, {bool signed = false}) => signed
      ? Money.signedWallet(v, decimals: 0)
      : Money.wallet(v, decimals: 0);

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanService>();
    final lot = widget.lotSize;
    final stats = StrategyMath.stats(_legs, lot);
    final net = StrategyMath.netPremium(_legs, lot);
    final margin = StrategyMath.marginRequired(_legs, lot);
    final daysLeft = math.max(0.0, _dte - _daysPassed);
    final whatIfSpot = widget.spot * (1 + _movePct / 100);
    final whatIfPnl = StrategyMath.pnlAt(
      _legs,
      whatIfSpot,
      daysLeft,
      lot,
      symbol: widget.underlying,
    );
    final greeks = StrategyMath.greeks(
      _legs,
      widget.spot,
      _dte,
      lot,
      symbol: widget.underlying,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                10,
                AppSpacing.lg,
                6,
              ),
              child: Row(
                children: [
                  AuthIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Strategy builder',
                          style: AppFonts.sans(
                            size: 18,
                            weight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          '${widget.underlying} · expiry ${widget.expiry} · lot $lot · spot ${Money.bare(widget.spot, from: _src)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.mono(
                            size: 11.5,
                            color: AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _tierPill(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  6,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  SizedBox(
                    height: 54,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final p in StrategyPreset.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _presetChip(p),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final (i, l) in _legs.indexed) _legRow(i, l),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _legs.length >= 6 ? null : _addLeg,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add leg'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _card(
                    Column(
                      children: [
                        _stat(
                          net >= 0 ? 'Net credit' : 'Net debit',
                          _money(net.abs()),
                          color: net >= 0 ? AppColors.bull : AppColors.ink,
                        ),
                        _stat(
                          'Max profit',
                          stats.maxProfit == null
                              ? 'Unlimited'
                              : _money(stats.maxProfit!),
                          color: AppColors.bull,
                        ),
                        _stat(
                          'Max loss',
                          stats.maxLoss == null
                              ? 'Unlimited'
                              : _money(stats.maxLoss!.abs()),
                          color: AppColors.bear,
                        ),
                        _stat(
                          'Breakeven',
                          stats.breakevens.isEmpty
                              ? '—'
                              : stats.breakevens
                                    .map((b) => Money.bare(b, from: _src))
                                    .join('  ·  '),
                        ),
                        _stat('Cash needed', _money(margin)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PAYOFF', style: AppText.sectionLabel),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 190,
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _PayoffPainter(
                              legs: _legs,
                              lot: lot,
                              spot: widget.spot,
                              daysLeft: daysLeft,
                              symbol: widget.underlying,
                              marker: whatIfSpot,
                              bull: AppColors.bull,
                              bear: AppColors.bear,
                              line: AppColors.ink,
                              grid: AppColors.birch,
                              today: AppColors.goldMid,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _legend(AppColors.ink, 'At expiry'),
                            const SizedBox(width: 14),
                            _legend(
                              AppColors.goldMid,
                              daysLeft > 0
                                  ? 'In ${_daysPassed.round()} day${_daysPassed.round() == 1 ? '' : 's'}'
                                  : 'At expiry',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WHAT IF', style: AppText.sectionLabel),
                        const SizedBox(height: 6),
                        Text(
                          'If ${widget.underlying} moves ${_movePct >= 0 ? '+' : ''}${_movePct.toStringAsFixed(1)}% to ${Money.bare(whatIfSpot, from: _src)} '
                          '${_daysPassed.round() == 0 ? 'today' : 'in ${_daysPassed.round()} days'}, this strategy makes',
                          style: AppFonts.sans(size: 13, color: AppColors.ink2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _money(whatIfPnl, signed: true),
                          style: AppFonts.mono(
                            size: 22,
                            weight: FontWeight.w700,
                            color: whatIfPnl >= 0
                                ? AppColors.bull
                                : AppColors.bear,
                          ),
                        ),
                        Slider(
                          value: _movePct,
                          min: -10,
                          max: 10,
                          divisions: 80,
                          label: '${_movePct.toStringAsFixed(1)}%',
                          onChanged: (v) => setState(() => _movePct = v),
                        ),
                        Text(
                          'Days from now: ${_daysPassed.round()} of ${_dte.ceil()}',
                          style: AppFonts.sans(size: 12, color: AppColors.ink3),
                        ),
                        Slider(
                          value: _daysPassed.clamp(0, math.max(0.0, _dte)),
                          min: 0,
                          max: math.max(1.0, _dte),
                          divisions: math.max(1, _dte.ceil()),
                          onChanged: (v) => setState(() => _daysPassed = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GREEKS (WHOLE STRATEGY)',
                          style: AppText.sectionLabel,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _greek(
                              'Delta',
                              greeks.delta.toStringAsFixed(1),
                              'per ₹1 move',
                            ),
                            _greek(
                              'Gamma',
                              greeks.gamma.toStringAsFixed(3),
                              'delta change',
                            ),
                            _greek(
                              'Theta',
                              _money(greeks.theta, signed: true),
                              'per day',
                            ),
                            _greek(
                              'Vega',
                              _money(greeks.vega, signed: true),
                              'per 1% IV',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Estimates from the app\'s pricing model (assumed volatility, not live IV). Practice only, not advice.',
                    style: AppFonts.sans(size: 11, color: AppColors.ink4),
                  ),
                  if (!plan.hasTitanTools) ...[
                    const SizedBox(height: 12),
                    const LockedFeatureCard(
                      title: 'Place the whole strategy in one tap',
                      message:
                          'Try any strategy here for free. Titan places every leg together as one basket, with unlimited F&O trades.',
                      needsTitan: true,
                      source: 'strategy_builder',
                    ),
                  ],
                ],
              ),
            ),
            _footer(plan),
          ],
        ),
      ),
    );
  }

  Widget _tierPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: AppCard.badge(AppColors.violetLight),
    child: Text(
      'TITAN',
      style: AppFonts.sans(
        size: 10,
        weight: FontWeight.w700,
        color: AppColors.violet,
      ),
    ),
  );

  Widget _presetChip(StrategyPreset p) {
    final on = p == _preset;
    return Material(
      color: on ? AppColors.goldPale : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          ChurnTelemetryService.instance.recordButtonTap(
            'strategy_preset_${p.name}',
          );
          _apply(p);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.label,
                style: AppFonts.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: on ? AppColors.goldMid : AppColors.ink,
                ),
              ),
              Text(
                p.view,
                style: AppFonts.sans(size: 11, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(
    String a,
    String b,
    bool first,
    VoidCallback onTap, {
    Color? colorA,
    Color? colorB,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.tag),
    child: Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            (first ? (colorA ?? AppColors.goldMid) : (colorB ?? AppColors.ink3))
                .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.tag),
      ),
      child: Text(
        first ? a : b,
        style: AppFonts.sans(
          size: 12,
          weight: FontWeight.w700,
          color: first
              ? (colorA ?? AppColors.goldMid)
              : (colorB ?? AppColors.ink3),
        ),
      ),
    ),
  );

  Widget _legRow(int i, StrategyLeg l) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.pureWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.birch),
    ),
    child: Row(
      children: [
        _toggle(
          'BUY',
          'SELL',
          l.buy,
          () => setState(() {
            l.buy = !l.buy;
            _preset = null;
          }),
          colorA: AppColors.bull,
          colorB: AppColors.bear,
        ),
        const SizedBox(width: 6),
        _toggle(
          'CE',
          'PE',
          l.isCall,
          () => setState(() {
            l.type = l.isCall ? 'PE' : 'CE';
            _repriceLeg(l);
            _preset = null;
          }),
        ),
        const SizedBox(width: 4),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => _stepStrike(l, -1),
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                Money.bare(l.strike, decimals: 0, from: _src),
                style: AppFonts.mono(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '@ ${Money.bare(l.premium, from: _src)}',
                style: AppFonts.mono(size: 11, color: AppColors.ink3),
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => _stepStrike(l, 1),
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
        InkWell(
          onTap: () => setState(() {
            l.lots = l.lots >= 10 ? 1 : l.lots + 1;
            _preset = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              '${l.lots}x',
              style: AppFonts.mono(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Remove leg',
          onPressed: () => setState(() {
            _legs.removeAt(i);
            _preset = null;
          }),
          icon: Icon(Icons.close_rounded, size: 18, color: AppColors.ink4),
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.pureWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.birch),
    ),
    child: child,
  );

  Widget _stat(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label, style: AppFonts.sans(size: 13, color: AppColors.ink3)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppFonts.mono(
              size: 13,
              weight: FontWeight.w600,
              color: color ?? AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _greek(String name, String value, String hint) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: AppFonts.sans(size: 11, color: AppColors.ink3)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.mono(
            size: 13,
            weight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        Text(hint, style: AppFonts.sans(size: 10, color: AppColors.ink4)),
      ],
    ),
  );

  Widget _legend(Color c, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 14, height: 3, color: c),
      const SizedBox(width: 6),
      Text(text, style: AppFonts.sans(size: 11, color: AppColors.ink3)),
    ],
  );

  Widget _footer(PlanService plan) {
    final ready =
        _legs.isNotEmpty && _legs.every((l) => l.symbol != null) && !_placing;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 14),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        border: Border(top: BorderSide(color: AppColors.birch)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: !ready
              ? null
              : () {
                  if (!plan.hasTitanTools) {
                    showUpgradeSheet(
                      context,
                      title: 'Basket orders are a Titan feature',
                      message:
                          'Titan places every leg of a strategy in one tap, with unlimited F&O trades.',
                      needsTitan: true,
                      source: 'strategy_place',
                    );
                    return;
                  }
                  _confirmAndPlace();
                },
          icon: _placing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  plan.hasTitanTools
                      ? Icons.playlist_add_check_rounded
                      : Icons.lock_rounded,
                ),
          label: Text(
            _placing
                ? 'Placing…'
                : 'Place ${_legs.length} leg${_legs.length == 1 ? '' : 's'} at market',
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndPlace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Place this strategy?'),
        content: Text(
          [
            for (final l in _legs)
              '${l.buy ? 'BUY' : 'SELL'} ${l.lots} lot ${widget.underlying} ${l.strike.toStringAsFixed(0)} ${l.type}',
            '',
            'Bought legs go first so sold legs are covered. Each leg is a market order.',
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Place'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ChurnTelemetryService.instance.recordButtonTap(
      'strategy_place_basket',
      extra: {'legs': _legs.length, 'preset': _preset?.name ?? 'custom'},
    );
    setState(() => _placing = true);
    final ordered = [..._legs]
      ..sort((a, b) => (b.buy ? 1 : 0) - (a.buy ? 1 : 0));
    final failed = <String>[];
    var placed = 0;
    for (final l in ordered) {
      try {
        await SupabaseService().placeOrder(
          symbol: l.symbol!,
          market: widget.market,
          side: l.buy ? 'buy' : 'sell',
          quantity: (l.lots * widget.lotSize).toDouble(),
          price: l.premium,
          isMarket: true,
          instrumentType: 'OPTION',
          strikePrice: l.strike,
          optionType: l.type,
          expiryDate: widget.expiry,
        );
        placed++;
      } catch (e) {
        failed.add(
          '${l.strike.toStringAsFixed(0)} ${l.type}: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
    if (!mounted) return;
    setState(() => _placing = false);
    await context.read<AuthService>().refreshUser();
    PlanService.instance.refreshUsage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: failed.isEmpty ? 4 : 10),
        backgroundColor: failed.isEmpty ? AppColors.bull : AppColors.bear,
        content: Text(
          failed.isEmpty
              ? 'All $placed legs placed.'
              : '$placed of ${ordered.length} legs placed. Failed: ${failed.join('; ')}',
        ),
      ),
    );
  }
}

class _PayoffPainter extends CustomPainter {
  _PayoffPainter({
    required this.legs,
    required this.lot,
    required this.spot,
    required this.daysLeft,
    required this.symbol,
    required this.marker,
    required this.bull,
    required this.bear,
    required this.line,
    required this.grid,
    required this.today,
  });

  final List<StrategyLeg> legs;
  final int lot;
  final double spot, daysLeft, marker;
  final String symbol;
  final Color bull, bear, line, grid, today;

  @override
  void paint(Canvas canvas, Size size) {
    if (legs.isEmpty || size.width <= 0) return;
    final lo = spot * 0.88, hi = spot * 1.12;
    const n = 120;
    final xs = [for (var i = 0; i <= n; i++) lo + (hi - lo) * i / n];
    final expiry = [
      for (final x in xs) StrategyMath.payoffAtExpiry(legs, x, lot),
    ];
    final now = [
      for (final x in xs)
        StrategyMath.pnlAt(legs, x, daysLeft, lot, symbol: symbol),
    ];
    var minY = [...expiry, ...now].reduce(math.min),
        maxY = [...expiry, ...now].reduce(math.max);
    if (minY > 0) minY = 0;
    if (maxY < 0) maxY = 0;
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;

    double px(double x) => (x - lo) / (hi - lo) * size.width;
    double py(double y) =>
        size.height - (y - minY) / (maxY - minY) * size.height;

    final zeroY = py(0);
    final fill = Path()..moveTo(px(xs.first), zeroY);
    for (var i = 0; i <= n; i++) {
      fill.lineTo(px(xs[i]), py(expiry[i]));
    }
    fill
      ..lineTo(px(xs.last), zeroY)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, zeroY));
    canvas.drawPath(fill, Paint()..color = bull.withValues(alpha: 0.14));
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, zeroY, size.width, size.height));
    canvas.drawPath(fill, Paint()..color = bear.withValues(alpha: 0.14));
    canvas.restore();

    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    final spotX = px(spot);
    canvas.drawLine(
      Offset(spotX, 0),
      Offset(spotX, size.height),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    final mX = px(marker.clamp(lo, hi));
    canvas.drawLine(
      Offset(mX, 0),
      Offset(mX, size.height),
      Paint()
        ..color = today.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    Path pathOf(List<double> ys) {
      final p = Path()..moveTo(px(xs.first), py(ys.first));
      for (var i = 1; i <= n; i++) {
        p.lineTo(px(xs[i]), py(ys[i]));
      }
      return p;
    }

    canvas.drawPath(
      pathOf(now),
      Paint()
        ..color = today
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      pathOf(expiry),
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _PayoffPainter old) => true;
}
