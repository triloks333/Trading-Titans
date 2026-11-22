import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../services/supabase_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/upgrade_sheet.dart';
import 'stock_detail_screen.dart';

/// Execution grade from a trade's return in percent.
({String grade, String verdict}) autopsyGrade(double pct) => switch (pct) {
      >= 10 => (grade: 'A+', verdict: 'Textbook trade'),
      >= 5 => (grade: 'A', verdict: 'Clean, well-managed win'),
      >= 2 => (grade: 'B', verdict: 'Solid win'),
      > 0 => (grade: 'B−', verdict: 'Small win: the exit came early'),
      > -2 => (grade: 'C', verdict: 'Small loss, cut in time'),
      > -5 => (grade: 'C−', verdict: 'Right idea, no exit plan'),
      _ => (grade: 'D', verdict: 'The loss ran too far'),
    };

/// Entry price implied by a closing order: a sell closed a long bought lower by
/// pnl/qty; a buy covered a short sold higher by the same.
double? autopsyEntryPrice(Order close) {
  if (close.quantity <= 0) return null;
  final perUnit = close.realizedPnl / close.quantity;
  return close.side == 'sell' ? close.price - perUnit : close.price + perUnit;
}

class AutopsyScreen extends StatefulWidget {
  const AutopsyScreen({super.key, this.data, this.orders});

  /// trade-autopsy output and orders to use instead of fetching (tests).
  final Map<String, dynamic>? data;
  final List<Order>? orders;

  @override
  State<AutopsyScreen> createState() => _AutopsyScreenState();
}

class _AutopsyScreenState extends State<AutopsyScreen> {
  late Future<List<Object>> _load = _fetch();
  int _picked = 0;
  final Map<String, List<double>> _paths = {};

  Future<List<Object>> _fetch() async => Future.wait<Object>([
        widget.data != null ? Future.value(widget.data!) : SupabaseService().getAutopsy(),
        widget.orders != null ? Future.value(widget.orders!) : SupabaseService().getOrders(limit: 200),
      ]);

  /// The closing order behind an insight, matched on symbol and realised P&L.
  Order? _match(List<Order> orders, Map<String, dynamic> i) {
    final pnl = (i['pnl'] as num?)?.toDouble() ?? 0;
    return orders.where((o) => o.symbol == i['symbol'] && (o.realizedPnl - pnl).abs() < 0.05).firstOrNull;
  }

  void _loadPath(String symbol, String market) {
    final key = '$symbol\x1F$market';
    if (_paths.containsKey(key) || widget.data != null) return;
    _paths[key] = const [];
    SupabaseService().getHistory(symbol, market, '1mo').then((pts) {
      if (mounted) setState(() => _paths[key] = [for (final p in pts) if (p['v'] is num) (p['v'] as num).toDouble()]);
    }).catchError((_) {});
  }

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
              Expanded(child: Text('Trade autopsy', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink))),
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
            child: FutureBuilder<List<Object>>(
              future: _load,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) {
                  return ErrorState(
                    message: "We couldn't load your autopsy. Check your connection and try again.",
                    onRetry: () => setState(() {
      _load = _fetch();
    }),
                  );
                }
                final data = snap.data![0] as Map<String, dynamic>;
                final orders = snap.data![1] as List<Order>;
                final insights = [for (final i in (data['insights'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
                if (insights.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.manage_search_rounded, size: 48, color: AppColors.ink4),
                        const SizedBox(height: AppSpacing.md),
                        Text('No trades to review yet', style: AppText.bodyBold),
                        const SizedBox(height: 4),
                        Text(data['summary'] as String? ?? 'Close a trade and its autopsy shows up here.',
                            textAlign: TextAlign.center, style: AppText.bodySmall),
                      ]),
                    ),
                  );
                }
                final pick = _picked.clamp(0, insights.length - 1);
                return Column(children: [
                  _tradeChips(insights, pick),
                  Expanded(child: _detail(insights[pick], _match(orders, insights[pick]))),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tradeChips(List<Map<String, dynamic>> insights, int pick) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
        child: Row(children: [
          for (final (i, t) in insights.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: i == pick ? AppColors.goldPale : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: i == pick ? AppColors.goldMid : AppColors.birch),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () {
                    ChurnTelemetryService.instance.recordButtonTap('autopsy_trade_chip_selector');
                    setState(() => _picked = i);
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (t['locked'] == true) ...[
                        Icon(Icons.lock_rounded, size: 12, color: AppColors.ink4),
                        const SizedBox(width: 4),
                      ],
                      Text('${t['symbol']}',
                          style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: i == pick ? AppColors.goldMid : AppColors.ink3)),
                      const SizedBox(width: 6),
                      Text(Money.signedWallet((t['pnl'] as num? ?? 0).toDouble(), decimals: 2),
                          style: AppFonts.mono(size: 13, color: (t['pnl'] as num? ?? 0) >= 0 ? AppColors.bull : AppColors.bear)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );

  BoxDecoration _card({Color? fill, Color? border}) => BoxDecoration(
        color: fill ?? AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border ?? AppColors.birch),
      );

  Widget _detail(Map<String, dynamic> t, Order? close) {
    final symbol = t['symbol'] as String? ?? '';
    final market = t['market'] as String? ?? 'stock';
    final pnl = (t['pnl'] as num? ?? 0).toDouble();
    final win = pnl > 0;
    final pct = ((t['loss_pct'] as num?)?.toDouble() ?? 0) * (win ? 1 : -1);
    final g = autopsyGrade(pct);
    final charges = (t['total_charges'] as num?)?.toDouble() ?? close?.totalCharges ?? 0;
    final entry = close == null ? null : autopsyEntryPrice(close);
    final tone = win ? AppColors.bull : AppColors.bear;
    _loadPath(symbol, market);
    final path = _paths['$symbol\x1F$market'] ?? const [];
    final when = (close?.executedAt ?? close?.createdAt)?.toLocal();
    final meta = [
      if (close?.orderType != null) close!.orderType![0].toUpperCase() + close.orderType!.substring(1),
      if (close != null) '${Money.quantity(close.quantity, market: market)} qty',
      if (when != null) 'closed ${DateFormat('d MMM').format(when)}',
    ].join(' · ');

    final checks = <(String, Color, String)>[
      (win ? '✓' : '✕', tone, t['reason'] as String? ?? (win ? 'Closed in profit.' : 'Closed at a loss.')),
      if (charges > 0)
        ('!', AppColors.titanGold, 'Charges ${Money.wallet(charges, decimals: 2)} — net ${Money.signedWallet(pnl - charges, decimals: 2)} after costs'),
      if (entry != null && close != null)
        ('·', AppColors.ink4,
            'Entered near ${Money.instrument(entry, market: market)}, exited at ${Money.instrument(close.price, market: market)}'),
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(symbol, style: AppFonts.sans(size: 17, weight: FontWeight.w700, color: AppColors.ink)),
                if (meta.isNotEmpty) Text(meta, style: AppFonts.mono(size: 12, color: AppColors.ink4)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.signedWallet(pnl, decimals: 2), style: AppFonts.mono(size: 20, weight: FontWeight.w600, color: tone)),
              Text('${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(2)}%', style: AppFonts.mono(size: 12, color: tone)),
            ]),
          ]),
          const SizedBox(height: 12),
          Semantics(
            label: 'Price over the last month with entry and exit levels',
            child: SizedBox(
              height: 110,
              child: path.length < 2
                  ? null
                  : CustomPaint(
                      painter: _PathPainter(path, entry: entry, exit: close?.price, line: AppColors.ink3, entryColor: AppColors.goldMid, exitColor: tone),
                    ),
            ),
          ),
        ]),
      ),
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Row(children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: win ? AppColors.bull : AppColors.titanGold, width: 5)),
            child: Text(g.grade, style: AppFonts.mono(size: 20, weight: FontWeight.w600, color: AppColors.ink)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('EXECUTION GRADE', style: AppText.sectionLabel),
              const SizedBox(height: 2),
              Text(g.verdict, style: AppText.bodyBold),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Text('WHAT HAPPENED', style: AppText.sectionLabel),
      for (final (mark, color, text) in checks)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 18, child: Text(mark, style: AppFonts.mono(size: 13, weight: FontWeight.w600, color: color))),
            Expanded(child: Text(text, style: AppFonts.sans(size: 13, color: AppColors.ink))),
          ]),
        ),
      // The server blanks the advice on trades past the free monthly allowance.
      if (t['locked'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: LockedFeatureCard(
            title: 'Lesson for this trade is locked',
            message: 'Free accounts get the full autopsy lesson on 3 trades a month. Pro unlocks every trade, every month.',
            source: 'autopsy_lesson',
          ),
        )
      else
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(14),
          decoration: _card(fill: AppColors.goldPale, border: AppColors.goldMid),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LESSON', style: AppText.sectionLabel.copyWith(color: AppColors.goldMid)),
            const SizedBox(height: 4),
            Text(t['advice'] as String? ?? 'Plan the exit before you enter.', style: AppFonts.sans(size: 14, color: AppColors.ink)),
          ]),
        ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(backgroundColor: AppColors.cream),
            onPressed: () => _share(symbol, pnl, pct, g.grade),
            child: const Text('Share P&L card'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              ChurnTelemetryService.instance.recordButtonTap('autopsy_retake_trade_on_stock_btn', extra: {'sym': symbol});
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StockDetailScreen(symbol: symbol, market: market, name: t['name'] as String? ?? symbol)));
            },
            child: const Text('Trade again'),
          ),
        ),
      ]),
    ]);
  }

  /// WhatsApp, or copy the text when WhatsApp cannot open.
  Future<void> _share(String symbol, double pnl, double pct, String grade) async {
    final text = '${pnl >= 0 ? '📈' : '📉'} $symbol ${Money.signedWallet(pnl, decimals: 2)} '
        '(${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(2)}%) · grade $grade on Trading Titans paper trading\n'
        'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans';
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.chat_rounded), title: const Text('Share on WhatsApp'), onTap: () => Navigator.pop(s, 'wa')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Copy text'), onTap: () => Navigator.pop(s, 'copy')),
        ]),
      ),
    );
    if (choice == 'wa' && await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication)) {
      return;
    }
    if (choice == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('P&L card copied')));
  }
}

/// Closing prices with dashed ENTRY and EXIT levels.
class _PathPainter extends CustomPainter {
  _PathPainter(this.values, {this.entry, this.exit, required this.line, required this.entryColor, required this.exitColor});
  final List<double> values;
  final double? entry, exit;
  final Color line, entryColor, exitColor;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...values, ?entry, ?exit];
    final lo = all.reduce((a, b) => a < b ? a : b), hi = all.reduce((a, b) => a > b ? a : b);
    final span = hi == lo ? 1.0 : hi - lo;
    double y(double v) => 8 + (size.height - 16) * (1 - (v - lo) / span);
    final path = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(size.width * i / (values.length - 1), y(values[i]));
    }
    canvas.drawPath(path, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
    void level(double v, Color c, String label) {
      final p = Paint()
        ..color = c
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y(v)), Offset((x + 3).clamp(0, size.width), y(v)), p);
      }
      (TextPainter(text: TextSpan(text: label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)), textDirection: TextDirection.ltr)
            ..layout())
          .paint(canvas, Offset(label == 'ENTRY' ? 4 : size.width - 30, y(v) - 14));
    }

    if (entry != null) level(entry!, entryColor, 'ENTRY');
    if (exit != null) level(exit!, exitColor, 'EXIT');
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.values != values || old.entry != entry || old.exit != exit;
}
