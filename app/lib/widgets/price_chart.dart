import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';

class PriceChart extends StatelessWidget {
  final List<Map<String, dynamic>> points;
  final bool isPositive;

  const PriceChart({super.key, required this.points, required this.isPositive});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return       SizedBox(
        height: 200,
        child: Center(child: Text('No data', style: TextStyle(color: AppColors.ink4))),
      );
    }

    final spots = points.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), (e.value['v'] as num).toDouble());
    }).toList();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final padding = range * 0.05;
    final color = isPositive ? AppColors.bull : AppColors.bear;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            horizontalInterval: range / 3,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.birch.withValues(alpha: 0.5),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
            drawVerticalLine: false,
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '₹${value.toStringAsFixed(0)}',
                    style:       TextStyle(fontSize: 10, color: AppColors.ink4),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY - padding,
          maxY: maxY + padding,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: index == spots.length - 1 ? 4 : 0,
                    color: color,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '₹${spot.y.toStringAsFixed(2)}',
                    TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}
