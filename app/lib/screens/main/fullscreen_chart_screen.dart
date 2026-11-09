import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/instrument_chart.dart';
import 'order_entry_screen.dart';

/// Full-screen chart. Timeframes, indicators, drawing tools and the OHLC legend
/// all live inside the chart page (see [InstrumentChart]); this screen adds the
/// header, rotation and the Sell / Buy bar.
class FullscreenChartScreen extends StatefulWidget {
  final String symbol;
  final String market;
  final String name;
  final Quote? quote;

  const FullscreenChartScreen({
    super.key,
    required this.symbol,
    required this.market,
    required this.name,
    this.quote,
  });

  @override
  State<FullscreenChartScreen> createState() => _FullscreenChartScreenState();
}

class _FullscreenChartScreenState extends State<FullscreenChartScreen> {
  Key _chartKey = UniqueKey();
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    SystemChrome.setPreferredOrientations(_isLandscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  Future<void> _order(bool isBuy) async {
    ChurnTelemetryService.instance.recordButtonTap(isBuy ? 'pro_chart_quick_buy_btn' : 'pro_chart_quick_sell_btn', extra: {'sym': widget.symbol});
    if (widget.quote == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderEntryScreen(quote: widget.quote!, isBuy: isBuy)));
  }

  String get _exchange => switch (widget.market) {
        'crypto' => 'CRYPTO',
        'us_stock' => 'US',
        'commodity' => 'COMMODITY',
        _ => 'NSE',
      };

  String get _display => widget.symbol.replaceFirst(RegExp(r'^(NSE|BSE):'), '').replaceAll(RegExp(r'-(EQ|SM|BE|BZ)$'), '');

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
              child: Row(children: [
                AuthIconButton(icon: Icons.close_rounded, label: 'Close chart', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$_display · $_exchange',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 14, weight: FontWeight.w700, color: AppColors.ink)),
                    if (q != null) _ohlc(q),
                  ]),
                ),
                AuthIconButton(icon: Icons.refresh_rounded, label: 'Reload chart', onTap: () => setState(() => _chartKey = UniqueKey())),
                const SizedBox(width: 6),
                AuthIconButton(
                  icon: _isLandscape ? Icons.stay_current_portrait_rounded : Icons.screen_rotation_rounded,
                  label: _isLandscape ? 'Portrait' : 'Landscape',
                  onTap: _toggleOrientation,
                ),
                const SizedBox(width: 6),
                AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ]),
            ),
            Expanded(
              child: InstrumentChart(
                key: _chartKey,
                symbol: widget.symbol,
                market: widget.market,
                theme: AppColors.isDark ? 'dark' : 'light',
                livePrice: q?.price,
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.birch))),
              child: Row(children: [
                Expanded(child: _side(false)),
                const SizedBox(width: 10),
                Expanded(child: _side(true)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// "O 2,918.4  H 2,956.0  L 2,911.1  C 2,948.3", close tinted by direction.
  Widget _ohlc(Quote q) {
    String n(double v) => Money.bare(v, from: Money.sourceFor(widget.market));
    TextSpan k(String l) => TextSpan(text: '$l ', style: AppFonts.mono(size: 11, color: AppColors.ink4));
    return Text.rich(
      TextSpan(style: AppFonts.mono(size: 11, color: AppColors.ink), children: [
        if (q.open != null) ...[k('O'), TextSpan(text: '${n(q.open!)}  ')],
        if (q.dayHigh != null) ...[k('H'), TextSpan(text: '${n(q.dayHigh!)}  ')],
        if (q.dayLow != null) ...[k('L'), TextSpan(text: '${n(q.dayLow!)}  ')],
        k('C'),
        TextSpan(text: n(q.price), style: TextStyle(color: q.change >= 0 ? AppColors.bull : AppColors.bear)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _side(bool isBuy) => SizedBox(
        height: 46,
        child: ElevatedButton(
          onPressed: widget.quote == null ? null : () => _order(isBuy),
          style: ElevatedButton.styleFrom(
            backgroundColor: isBuy ? AppColors.bull : AppColors.bear,
            foregroundColor: isBuy && AppColors.isDark ? const Color(0xFF04140B) : Colors.white,
          ),
          child: Text(isBuy ? 'Buy' : 'Sell'),
        ),
      );
}
