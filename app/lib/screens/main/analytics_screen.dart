import 'package:flutter/material.dart';

import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../services/supabase_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/error_state.dart';
import 'autopsy_screen.dart';
import '../../services/action_reaction_engine.dart';
import '../../services/plan_service.dart';
import '../../widgets/upgrade_sheet.dart';

/// Period chips and how far back each looks.
const Map<String, Duration?> kAnalyticsPeriods = {'1W': Duration(days: 7), '1M': Duration(days: 30), '3M': Duration(days: 90), 'All': null};

/// Performance over closed trades. Only orders that realised P&L count: an
/// opening buy is not a win or a loss, so counting it (as the old screen did)
/// dragged every win rate down.
class TradeStats {
  TradeStats._(this.closes);

  factory TradeStats.from(List<Order> orders, {Duration? period, DateTime? now}) {
    final since = period == null ? null : (now ?? DateTime.now()).subtract(period);
    final closes = orders
        .where((o) => o.realizedPnl != 0 && _at(o) != null && (since == null || _at(o)!.isAfter(since)))
        .toList()
      ..sort((a, b) => _at(a)!.compareTo(_at(b)!));
    return TradeStats._(closes);
  }

  static DateTime? _at(Order o) => o.executedAt ?? o.createdAt;

  final List<Order> closes;

  Iterable<double> get _wins => closes.map((o) => o.realizedPnl).where((p) => p > 0);
  Iterable<double> get _losses => closes.map((o) => o.realizedPnl).where((p) => p < 0);

  int get trades => closes.length;
  double get total => closes.fold(0.0, (s, o) => s + o.realizedPnl);
  double get winRate => trades == 0 ? 0 : _wins.length / trades * 100;
  double get avgWin => _wins.isEmpty ? 0 : _wins.reduce((a, b) => a + b) / _wins.length;
  double get avgLoss => _losses.isEmpty ? 0 : _losses.reduce((a, b) => a + b) / _losses.length;

  /// Gross profit over gross loss; infinite with wins and no losses.
  double get profitFactor {
    final gain = _wins.fold(0.0, (a, b) => a + b), loss = _losses.fold(0.0, (a, b) => a + b).abs();
    return loss == 0 ? (gain > 0 ? double.infinity : 0) : gain / loss;
  }

  /// Running realised P&L, starting at 0.
  List<double> get curve {
    var sum = 0.0;
    return [0, for (final o in closes) sum += o.realizedPnl];
  }

  /// Largest fall from a running peak of the curve, as a negative amount.
  double get maxDrawdown {
    var peak = 0.0, worst = 0.0;
    for (final v in curve) {
      if (v > peak) peak = v;
      if (v - peak < worst) worst = v - peak;
    }
    return worst;
  }

  /// Realised P&L per IST trading day, oldest first, last [days] active days.
  List<(DateTime, double)> daily({int days = 14}) {
    final byDay = <DateTime, double>{};
    for (final o in closes) {
      final d = MarketHours.istDate(_at(o)!);
      byDay[d] = (byDay[d] ?? 0) + o.realizedPnl;
    }
    final keys = byDay.keys.toList()..sort();
    return [for (final k in keys.skip(keys.length > days ? keys.length - days : 0)) (k, byDay[k]!)];
  }

  /// Realised P&L per market, F&O split out from cash equity.
  Map<String, double> get byMarket {
    final out = <String, double>{};
    for (final o in closes) {
      final fo = o.instrumentType == 'OPTION' || o.instrumentType == 'FUTURE';
      final k = fo
          ? 'F&O'
          : switch (o.market) {
              'us_stock' => 'US',
              'crypto' => 'Crypto',
              'commodity' => 'Commodities',
              'pakistan_stock' => 'Pakistan',
              'italy_stock' => 'Italy',
              _ => 'India',
            };
      out[k] = (out[k] ?? 0) + o.realizedPnl;
    }
    return out;
  }

  /// One plain-English lesson from the numbers, for the Autopsy card.
  ({String title, String detail})? get insight {
    if (trades < 3) return null;
    if (avgLoss.abs() > avgWin && avgWin > 0) {
      return (
        title: 'Your biggest leak: losses bigger than wins',
        detail: 'Average loss is ${(avgLoss.abs() / avgWin).toStringAsFixed(1)}× your average win',
      );
    }
    if (winRate < 50) return (title: 'Fewer than half your trades win', detail: 'Win rate ${winRate.round()}% — see what the losers share');
    return (title: 'Your edge is working', detail: 'Win rate ${winRate.round()}% with profit factor ${profitFactor.isInfinite ? '∞' : profitFactor.toStringAsFixed(2)}');
  }
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.orders});

  /// Orders to analyse instead of fetching them (tests).
  final List<Order>? orders;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late Future<List<Order>> _orders = _fetch();
  late String _period = PlanService.instance.historyDays == null ? '1M' : '1W';

  Future<List<Order>> _fetch() async => widget.orders ?? SupabaseService().getOrders(limit: 1000);

  String _signed(double v) => '${v >= 0 ? '+' : '−'}${Money.wallet(v.abs(), decimals: 2)}';
  Color _tone(double v) => v >= 0 ? AppColors.bull : AppColors.bear;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text('Analytics', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
            child: Row(children: [
              for (final p in kAnalyticsPeriods.keys) ...[
                if (p != '1W') const SizedBox(width: 6),
                Expanded(child: _chip(p)),
              ],
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<Order>>(
              future: _orders,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) {
                  return ErrorState(
                    message: "We couldn't load your analytics. Check your connection and try again.",
                    onRetry: () => setState(() {
      _orders = _fetch();
    }),
                  );
                }
                final s = TradeStats.from(snap.data ?? const [], period: kAnalyticsPeriods[_period]);
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
      _orders = _fetch();
    });
                    await _orders;
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 20),
                    children: [
                      _kpis(s),
                      if (s.trades == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text('No closed trades in this period yet. Close a position to see your stats.',
                              textAlign: TextAlign.center, style: AppText.body),
                        )
                      else ...[
                        _equity(s),
                        _dailyBars(s),
                        _markets(s),
                      ],
                      _autopsyCard(s),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  /// A period longer than the plan's history allowance (free: 7 days).
  bool _locked(String p) {
    final days = PlanService.instance.historyDays;
    if (days == null) return false;
    final d = kAnalyticsPeriods[p];
    return d == null || d.inDays > days;
  }

  Widget _chip(String p) => Material(
        color: p == _period ? AppColors.goldPale : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm), side: BorderSide(color: p == _period ? AppColors.goldMid : AppColors.birch)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () {
            ChurnTelemetryService.instance.recordButtonTap('analytics_period_1w_1m_3m_all_chip');
            if (_locked(p)) {
              showUpgradeSheet(context,
                  title: 'Full history is a Pro feature',
                  message: 'Free accounts see the last 7 days of analytics. Pro unlocks your full P&L history.',
                  source: 'analytics_period');
              return;
            }
            setState(() => _period = p);
          },
          child: Container(
            height: 32,
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_locked(p)) ...[Icon(Icons.lock_rounded, size: 11, color: AppColors.ink4), const SizedBox(width: 3)],
              Text(p, style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: p == _period ? AppColors.goldMid : AppColors.ink3)),
            ]),
          ),
        ),
      );

  BoxDecoration get _card => BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      );

  Widget _kpis(TradeStats s) {
    Widget kpi(String label, String value, {Color? color, bool right = true, bool bottom = true, double size = 18}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                right: right ? BorderSide(color: AppColors.birch) : BorderSide.none,
                bottom: bottom ? BorderSide(color: AppColors.birch) : BorderSide.none,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppFonts.sans(size: 11, color: AppColors.ink4)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: AppFonts.mono(size: size, weight: FontWeight.w600, color: color ?? AppColors.ink)),
              ),
            ]),
          ),
        );
    final pf = s.profitFactor;
    return Container(
      decoration: _card,
      child: Column(children: [
        Row(children: [
          kpi('Win rate', '${s.winRate.round()}%'),
          kpi('Profit factor', pf.isInfinite ? '∞' : pf.toStringAsFixed(2)),
          kpi('Trades', '${s.trades}', right: false),
        ]),
        Row(children: [
          kpi('Avg win', _signed(s.avgWin), color: AppColors.bull, bottom: false, size: 16),
          kpi('Avg loss', _signed(s.avgLoss), color: s.avgLoss < 0 ? AppColors.bear : AppColors.ink, bottom: false, size: 16),
          kpi('Max drawdown', _signed(s.maxDrawdown), color: s.maxDrawdown < 0 ? AppColors.bear : AppColors.ink, right: false, bottom: false, size: 16),
        ]),
      ]),
    );
  }

  Widget _section(String title, Widget child, {Widget? trailing}) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: _card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(title.toUpperCase(), style: AppText.sectionLabel)), ?trailing]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _equity(TradeStats s) => _section(
        'Equity curve · realised',
        trailing: Text(_signed(s.total), style: AppFonts.mono(size: 13, color: _tone(s.total))),
        Semantics(
          label: 'Realised P&L over $_period, ${_signed(s.total)}',
          child: SizedBox(height: 120, child: CustomPaint(painter: _CurvePainter(s.curve, AppColors.goldMid, AppColors.ink4))),
        ),
      );

  Widget _dailyBars(TradeStats s) {
    final days = s.daily();
    final up = days.where((d) => d.$2 > 0).length;
    return _section(
      'Daily P&L · last ${days.length} sessions',
      Semantics(
        label: 'Daily profit and loss: $up green days, ${days.length - up} red days',
        child: SizedBox(
          height: 110,
          child: CustomPaint(painter: _BarsPainter([for (final d in days) d.$2], AppColors.bull, AppColors.bear, AppColors.birch)),
        ),
      ),
    );
  }

  Widget _markets(TradeStats s) {
    final rows = s.byMarket.entries.toList()..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final max = rows.isEmpty ? 1.0 : rows.first.value.abs();
    return _section(
      'P&L by market',
      Column(children: [
        for (final e in rows)
          SizedBox(
            height: 30,
            child: Row(children: [
              SizedBox(width: 70, child: Text(e.key, style: AppFonts.sans(size: 13, color: AppColors.ink3))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : e.value.abs() / max,
                    minHeight: 8,
                    color: _tone(e.value),
                    backgroundColor: AppColors.cream,
                  ),
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(_signed(e.value), textAlign: TextAlign.right, style: AppFonts.mono(size: 13, color: _tone(e.value))),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _autopsyCard(TradeStats s) {
    final i = s.insight;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () {
            ChurnTelemetryService.instance.recordButtonTap('analytics_open_autopsy_leak_card');
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AutopsyScreen()));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i?.title ?? 'Trade autopsy', style: AppText.bodyBold),
                  Text(i?.detail ?? 'See why each trade won or lost', style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                  if (i?.title.startsWith('Your biggest leak') ?? false) ...[
                    const SizedBox(height: 6),
                    Builder(builder: (_) {
                      ActionReactionEngine.instance.analyticsLeakTip();
                      return Text(
                        'Tip: set a stop-loss when you enter, so each loss is capped at a size you chose.',
                        style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: AppColors.ink3),
                      );
                    }),
                  ],
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Line chart of the realised curve with a dashed zero line.
class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values, this.color, this.baseColor);
  final List<double> values;
  final Color color, baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi == lo ? 1.0 : hi - lo;
    double y(double v) => 6 + (size.height - 12) * (1 - (v - lo) / span);
    final zero = y(0);
    final dash = Paint()
      ..color = baseColor
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, zero), Offset((x + 3).clamp(0, size.width), zero), dash);
    }
    final path = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(size.width * i / (values.length - 1), y(values[i]));
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.values != values || old.color != color;
}

/// Up/down bars around a centre line, scaled to the largest day.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.up, this.down, this.axis);
  final List<double> values;
  final Color up, down, axis;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = axis);
    if (values.isEmpty) return;
    final max = values.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    final slot = size.width / values.length, w = (slot * 0.7).clamp(4.0, 16.0);
    for (var i = 0; i < values.length; i++) {
      final h = max == 0 ? 0.0 : values[i].abs() / max * (mid - 4);
      final x = slot * i + (slot - w) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, values[i] >= 0 ? mid - h : mid, w, h), const Radius.circular(2)),
        Paint()..color = values[i] >= 0 ? up : down,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.values != values;
}
