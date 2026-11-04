import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../services/supabase_service.dart';
import '../../widgets/error_state.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analytics', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink)),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: SupabaseService().getAnalytics(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: "We couldn't load your analytics. Check your connection and try again.",
              onRetry: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
              ),
            );
          }
          final data = snapshot.data ?? {};
          final pnl = (data['realized_pnl'] as num?)?.toDouble() ?? 0.0;
          final isProfit = pnl >= 0;
          
          final seriesList = (data['pnl_series'] as List<dynamic>?) ?? [];
          final dataPoints = seriesList.map((e) => (e['pnl'] as num).toDouble()).toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Hero P&L Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.pureWhite,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.birch),
                  boxShadow: AppShadows.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL REALIZED P&L',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink4,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          isProfit ? '+${Money.wallet(pnl, decimals: 2)}' : '-${Money.wallet(pnl.abs(), decimals: 2)}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: isProfit ? AppColors.bull : AppColors.bear,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isProfit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          color: isProfit ? AppColors.bull : AppColors.bear,
                          size: 28,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Equity Curve Graph Section
              if (dataPoints.isNotEmpty) ...[
                Text(
                  'Equity Curve',
                  style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  height: 180,
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: CustomPaint(
                    painter: PnlChartPainter(dataPoints),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Advanced Metrics Section Header
              Text(
                'Performance Metrics',
                style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Metrics Grid
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _metricTile(
                    'Win Rate', 
                    '${data['win_rate'] ?? 0}%',
                    subtitle: '${data['winning_trades'] ?? 0}W - ${data['losing_trades'] ?? 0}L',
                    progress: ((data['win_rate'] as num?)?.toDouble() ?? 0.0) / 100.0,
                  ),
                  _metricTile(
                    'Profit Factor', 
                    (data['profit_factor'] is double && (data['profit_factor'] as double).isInfinite)
                        ? '∞'
                        : (data['profit_factor'] as num?)?.toStringAsFixed(2) ?? '0.00',
                    subtitle: 'Gross profits / losses',
                  ),
                  _metricTile(
                    'Win/Loss Ratio', 
                    (data['win_loss_ratio'] as num?)?.toStringAsFixed(2) ?? '0.00',
                    subtitle: 'Avg Win / Avg Loss',
                  ),
                  _metricTile(
                    'Avg. Win', 
                    Money.wallet((data['avg_win'] as num?) ?? 0, decimals: 2),
                    subtitle: 'Profit per win trade',
                    valueColor: AppColors.bull,
                  ),
                  _metricTile(
                    'Avg. Loss', 
                    Money.wallet(((data['avg_loss'] as num?) ?? 0).abs(), decimals: 2),
                    subtitle: 'Loss per lost trade',
                    valueColor: AppColors.bear,
                  ),
                  _metricTile(
                    'Total Trades', 
                    '${data['total_trades'] ?? 0}',
                    subtitle: 'Buys: ${data['buy_trades'] ?? 0} • Sells: ${data['sell_trades'] ?? 0}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Best & Worst Trades
              Text(
                'Milestones',
                style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _milestoneTile(
                      'Best Trade',
                      data['best_trade'] as Map<String, dynamic>?,
                      isWin: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _milestoneTile(
                      'Worst Trade',
                      data['worst_trade'] as Map<String, dynamic>?,
                      isWin: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
      ),
    );
  }

  Widget _metricTile(String label, String value, {required String subtitle, double? progress, Color? valueColor}) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: AppText.sectionLabel.copyWith(fontSize: 10),
              ),
              if (progress != null)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.5,
                    color: AppColors.bull,
                    backgroundColor: AppColors.bearLight,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppFonts.mono(size: 19, weight: FontWeight.w600, color: valueColor ?? AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _milestoneTile(String label, Map<String, dynamic>? trade, {required bool isWin}) {
    final pnlVal = trade != null ? ((trade['realized_pnl'] as num?)?.toDouble() ?? 0.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isWin ? AppColors.bullLight.withValues(alpha: 0.15) : AppColors.bearLight.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: isWin ? AppColors.bull.withValues(alpha: 0.2) : AppColors.bear.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isWin ? AppColors.bull : AppColors.bear,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            trade?['symbol'] as String? ?? 'None',
            style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            trade != null
                ? '${isWin ? "+" : ""}${Money.wallet(pnlVal, decimals: 2)}'
                : '--',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isWin ? AppColors.bull : AppColors.bear,
            ),
          ),
        ],
      ),
    );
  }
}

class PnlChartPainter extends CustomPainter {
  final List<double> dataPoints;
  PnlChartPainter(this.dataPoints);

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final paintLine = Paint()
      ..color = AppColors.imperialGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()
      ..style = PaintingStyle.fill;

    final pathLine = Path();
    final pathFill = Path();

    final maxVal = dataPoints.fold<double>(0.001, (max, val) => val.abs() > max ? val.abs() : max);
    
    final double stepX = size.width / (dataPoints.length > 1 ? dataPoints.length - 1 : 1);
    final double centerY = size.height / 2;

    pathLine.moveTo(0, centerY - (dataPoints.first / maxVal) * (size.height / 2.2));
    pathFill.moveTo(0, size.height);
    pathFill.lineTo(0, centerY - (dataPoints.first / maxVal) * (size.height / 2.2));

    for (int i = 1; i < dataPoints.length; i++) {
      final double x = i * stepX;
      final double y = centerY - (dataPoints[i] / maxVal) * (size.height / 2.2);
      pathLine.lineTo(x, y);
      pathFill.lineTo(x, y);
    }
    
    pathFill.lineTo(size.width, size.height);
    pathFill.close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppColors.imperialGold.withValues(alpha: 0.25),
        AppColors.imperialGold.withValues(alpha: 0.0),
      ],
    );
    paintFill.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(pathFill, paintFill);
    canvas.drawPath(pathLine, paintLine);

    final paintBase = Paint()
      ..color = AppColors.birch
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paintBase);
  }

  @override
  bool shouldRepaint(covariant PnlChartPainter oldDelegate) {
    return oldDelegate.dataPoints != dataPoints;
  }
}
