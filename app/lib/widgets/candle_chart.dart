import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/candle.dart' as my_model;
import 'package:google_fonts/google_fonts.dart';
import 'package:interactive_chart/interactive_chart.dart';
import 'package:intl/intl.dart' as intl;
class CandleChart extends StatefulWidget {
  final List<my_model.CandleData> candles;
  final String selectedInterval;
  final ValueChanged<String> onIntervalChanged;
  final bool isPositive;

  const CandleChart({
    super.key,
    required this.candles,
    required this.selectedInterval,
    required this.onIntervalChanged,
    this.isPositive = true,
  });

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  static const _intervals = ['1m', '5m', '15m', '30m', '1h', '4h', '1d', '1w'];

  @override
  Widget build(BuildContext context) {
    // Map our CandleData model to interactive_chart's CandleData
    final chartData = widget.candles.map((c) => CandleData(
      timestamp: c.timestamp,
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close,
      volume: null,
    )).toList();

    return Column(
      children: [
        if (chartData.isEmpty)
          SizedBox(height: 280, child: Center(child: Text('No data', style: GoogleFonts.ibmPlexSans(color: AppColors.ink4))))
        else
          SizedBox(
            height: 280,
            child: InteractiveChart(
              candles: chartData,
              style:       ChartStyle(
                priceGainColor: AppColors.bull,
                priceLossColor: AppColors.bear,
                // Theme ink, not fixed near-black: those vanished on the dark palette.
                volumeColor: AppColors.ink4.withValues(alpha: 0.2), // Unused if volume is null
                priceGridLineColor: AppColors.birch,
                selectionHighlightColor: AppColors.ink.withValues(alpha: 0.2),
                overlayBackgroundColor: AppColors.pureWhite,
                overlayTextStyle: TextStyle(color: AppColors.ink, fontSize: 12),
              ),
              timeLabel: (timestamp, visibleDataCount) {
                final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
                final isDailyOrLonger = widget.selectedInterval.endsWith('d') || 
                                        widget.selectedInterval.endsWith('w') || 
                                        widget.selectedInterval.endsWith('mo');
                
                if (isDailyOrLonger) {
                  return intl.DateFormat('dd MMM yyyy').format(date);
                }
                
                // For intraday, just show the time to keep the chart clean and prevent overlap
                return intl.DateFormat('HH:mm').format(date);
              },
            ),
          ),
        const SizedBox(height: 8),
        _buildIntervalSelector(),
      ],
    );
  }

  Widget _buildIntervalSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _intervals.map((iv) {
          final selected = iv == widget.selectedInterval;
          return GestureDetector(
            onTap: () => widget.onIntervalChanged(iv),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.cream,
                borderRadius: BorderRadius.circular(AppRadius.tag),
                border: Border.all(color: selected ? AppColors.ink : AppColors.birch),
              ),
              child: Text(
                iv.toUpperCase(),
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.pureWhite : AppColors.ink4,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
