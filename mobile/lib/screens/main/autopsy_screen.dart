import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

class AutopsyScreen extends StatelessWidget {
  const AutopsyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loss Autopsy'),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: SupabaseService().getAutopsy(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load autopsy: ${snapshot.error}'));
          }
          final data = snapshot.data ?? {};
          final insights = (data['insights'] as List<dynamic>?) ?? [];
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Every loss is a lesson.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                Text(data['summary'] as String? ?? 'No losses to review yet.', style: const TextStyle(color: AppColors.ink4)),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: ListView.separated(
                    itemCount: insights.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final insight = insights[index] as Map<String, dynamic>;
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(AppRadius.xl), border: Border.all(color: AppColors.birch)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${insight['symbol']} • ${insight['market']?.toUpperCase() ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
                            const SizedBox(height: AppSpacing.xs),
                            Text(insight['reason'] as String? ?? 'Review this trade.', style: const TextStyle(color: AppColors.ink4)),
                            const SizedBox(height: AppSpacing.sm),
                            Text('Loss: ₹${(insight['loss'] as double).toStringAsFixed(0)}', style: const TextStyle(color: AppColors.bear, fontWeight: FontWeight.w700)),
                            const SizedBox(height: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(color: AppColors.goldPale, borderRadius: BorderRadius.circular(AppRadius.sm)),
                              child: Text(insight['advice'] as String? ?? 'Stay patient and respect risk.', style: const TextStyle(color: AppColors.ink3)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
