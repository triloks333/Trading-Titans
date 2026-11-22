import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/option_pricing.dart';
import '../../core/theme.dart';
import '../../models/position_model.dart';
import '../../services/plan_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/upgrade_sheet.dart';

/// The underlying a position is written on, matching the portfolio screen.
String underlyingOf(FoPosition p) =>
    (p.instrumentType == 'OPTION' && p.symbol.contains('-'))
    ? p.symbol.split('-').first
    : (p.instrumentType == 'FUTURE' && p.symbol.contains(' '))
    ? p.symbol.split(' ').first
    : p.symbol;

/// Greeks and a "what if the market moves" panel over open F&O positions (Titan).
///
/// Uses the exact pricing the Portfolio tab uses (same model, same session-close
/// clock), so today's P&L here matches the P&L shown there.
class OptionsRiskScreen extends StatefulWidget {
  const OptionsRiskScreen({
    super.key,
    required this.positions,
    required this.spots,
  });

  final List<FoPosition> positions;

  /// Underlying symbol to its spot price.
  final Map<String, double> spots;

  @override
  State<OptionsRiskScreen> createState() => _OptionsRiskScreenState();
}

class _OptionsRiskScreenState extends State<OptionsRiskScreen> {
  double _movePct = 0;
  double _daysAhead = 0;

  double _value(FoPosition p, double spot, double days) =>
      p.instrumentType == 'FUTURE'
      ? OptionPricing.futurePrice(spot: spot, daysToExpiry: days)
      : OptionPricing.optionPremium(
          optionType: p.optionType,
          spot: spot,
          strike: p.strikePrice,
          daysToExpiry: days,
        );

  Greeks _greeks(FoPosition p, double spot, double days) {
    final units = (p.netQty * p.lotSize).toDouble();
    if (p.instrumentType == 'FUTURE')
      return Greeks(delta: units, gamma: 0, theta: 0, vega: 0);
    return OptionPricing.greeks(
      optionType: p.optionType,
      spot: spot,
      strike: p.strikePrice,
      daysToExpiry: days,
    ).scale(units);
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanService>();
    final open = widget.positions
        .where((p) => p.netQty != 0 && widget.spots[underlyingOf(p)] != null)
        .toList();
    final byUnderlying = <String, List<FoPosition>>{};
    for (final p in open) {
      byUnderlying.putIfAbsent(underlyingOf(p), () => []).add(p);
    }

    var total = Greeks.zero;
    var pnlNow = 0.0, pnlThen = 0.0;
    for (final p in open) {
      final spot = widget.spots[underlyingOf(p)]!;
      final days = MarketHours.daysToExpiry(p.expiry);
      total = total + _greeks(p, spot, days);
      pnlNow += p.unrealizedPnl(_value(p, spot, days));
      final later = math.max(0.0, days - _daysAhead);
      pnlThen += p.unrealizedPnl(_value(p, spot * (1 + _movePct / 100), later));
    }
    final locked = !plan.hasTitanTools;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                10,
                AppSpacing.lg,
                10,
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
                    child: Text(
                      'Risk & Greeks',
                      style: AppFonts.sans(
                        size: 20,
                        weight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  if (open.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'No open F&O positions with a live price right now.',
                        textAlign: TextAlign.center,
                        style: AppText.body,
                      ),
                    )
                  else if (locked) ...[
                    const LockedFeatureCard(
                      title: 'See your Greeks and what-if P&L',
                      message:
                          'Titan shows delta, gamma, theta and vega for every position, and what you make or lose if the market moves.',
                      needsTitan: true,
                      source: 'options_risk',
                    ),
                    const SizedBox(height: 12),
                    for (final p in open) _positionTile(p, null),
                  ] else ...[
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHOLE PORTFOLIO', style: AppText.sectionLabel),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _greek(
                                'Delta',
                                total.delta.toStringAsFixed(1),
                                'P&L per ₹1 move',
                              ),
                              _greek(
                                'Gamma',
                                total.gamma.toStringAsFixed(3),
                                'delta change',
                              ),
                              _greek(
                                'Theta',
                                Money.signedWallet(total.theta, decimals: 0),
                                'per day',
                              ),
                              _greek(
                                'Vega',
                                Money.signedWallet(total.vega, decimals: 0),
                                'per 1% IV',
                              ),
                            ],
                          ),
                          if (total.theta < 0) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Time costs you about ${Money.wallet(-total.theta, decimals: 0)} a day if prices stand still.',
                              style: AppFonts.sans(
                                size: 12.5,
                                color: AppColors.bear,
                              ),
                            ),
                          ],
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
                            'If every underlying moves ${_movePct >= 0 ? '+' : ''}${_movePct.toStringAsFixed(1)}%'
                            '${_daysAhead.round() == 0 ? ' today' : ' over ${_daysAhead.round()} day${_daysAhead.round() == 1 ? '' : 's'}'}, your F&O P&L goes from',
                            style: AppFonts.sans(
                              size: 13,
                              color: AppColors.ink2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: Money.signedWallet(pnlNow, decimals: 0),
                                  style: AppFonts.mono(
                                    size: 15,
                                    color: AppColors.ink3,
                                  ),
                                ),
                                TextSpan(
                                  text: '  →  ',
                                  style: AppFonts.mono(
                                    size: 15,
                                    color: AppColors.ink3,
                                  ),
                                ),
                                TextSpan(
                                  text: Money.signedWallet(
                                    pnlThen,
                                    decimals: 0,
                                  ),
                                  style: AppFonts.mono(
                                    size: 22,
                                    weight: FontWeight.w700,
                                    color: pnlThen >= 0
                                        ? AppColors.bull
                                        : AppColors.bear,
                                  ),
                                ),
                              ],
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
                            'Days ahead: ${_daysAhead.round()}',
                            style: AppFonts.sans(
                              size: 12,
                              color: AppColors.ink3,
                            ),
                          ),
                          Slider(
                            value: _daysAhead,
                            min: 0,
                            max: 30,
                            divisions: 30,
                            onChanged: (v) => setState(() => _daysAhead = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final entry in byUnderlying.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Text(
                          '${entry.key} · spot ${Money.bare(widget.spots[entry.key]!, from: Money.sourceFor('stock'))}',
                          style: AppFonts.sans(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      for (final p in entry.value)
                        _positionTile(
                          p,
                          _greeks(
                            p,
                            widget.spots[entry.key]!,
                            MarketHours.daysToExpiry(p.expiry),
                          ),
                        ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Estimates from the app\'s pricing model (assumed volatility). Practice only, not advice.',
                    style: AppFonts.sans(size: 11, color: AppColors.ink4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _positionTile(FoPosition p, Greeks? g) {
    final name = p.instrumentType == 'OPTION'
        ? '${underlyingOf(p)} ${p.strikePrice.toStringAsFixed(0)} ${p.optionType}'
        : '${underlyingOf(p)} FUT';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: AppText.bodyBold)),
              Text(
                '${p.netQty > 0 ? 'LONG' : 'SHORT'} ${p.netQty.abs()} × ${p.lotSize}',
                style: AppFonts.mono(
                  size: 12,
                  color: p.netQty > 0 ? AppColors.bull : AppColors.bear,
                ),
              ),
            ],
          ),
          if (g != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _greek('Δ', g.delta.toStringAsFixed(1), null),
                _greek('Γ', g.gamma.toStringAsFixed(3), null),
                _greek('Θ/day', Money.signedWallet(g.theta, decimals: 0), null),
                _greek('Vega', Money.signedWallet(g.vega, decimals: 0), null),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.pureWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.birch),
    ),
    child: child,
  );

  Widget _greek(String name, String value, String? hint) => Expanded(
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
        if (hint != null)
          Text(hint, style: AppFonts.sans(size: 10, color: AppColors.ink4)),
      ],
    ),
  );
}
