import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
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
            return Center(child: Text('Could not load analytics: ${snapshot.error}'));
          }
          final data = snapshot.data ?? {};
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statCard('Total Realized P&L', '₹${data['realized_pnl']?.toStringAsFixed(0) ?? '0'}'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _smallStat('Trades', '${data['total_trades'] ?? 0}'),
                    _smallStat('Win Rate', '${data['win_rate'] ?? 0}%'),
                    _smallStat('Buys', '${data['buy_trades'] ?? 0}'),
                    _smallStat('Sells', '${data['sell_trades'] ?? 0}'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.ink4)),
        const SizedBox(height: AppSpacing.sm),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.ink)),
      ]),
    );
  }

  Widget _smallStat(String label, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.warmWhite, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppColors.birch)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.ink4)),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
      ]),
    );
  }
}
