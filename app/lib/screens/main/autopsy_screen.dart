import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

class AutopsyScreen extends StatelessWidget {
  const AutopsyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: SupabaseService().getAutopsy(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Autopsy', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.parchment,
              centerTitle: false,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Autopsy', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              backgroundColor: AppColors.parchment,
              centerTitle: false,
            ),
            body: Center(child: Text('Failed to load autopsy: ${snapshot.error}')),
          );
        }

        final data = snapshot.data ?? {};
        final insights = (data['insights'] as List<dynamic>?) ?? [];
        final profits = insights.where((i) => i['type'] == 'profit').toList();
        final losses = insights.where((i) => i['type'] == 'loss').toList();

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                'Autopsy',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink),
              ),
              backgroundColor: AppColors.parchment,
              centerTitle: false,
              bottom: TabBar(
                indicatorColor: AppColors.imperialGold,
                labelColor: AppColors.ink,
                unselectedLabelColor: AppColors.ink4,
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: [
                  Tab(text: 'All (${insights.length})'),
                  Tab(text: 'Profits (${profits.length})'),
                  Tab(text: 'Losses (${losses.length})'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildInsightList(context, data['summary'] as String?, insights),
                _buildInsightList(context, data['summary'] as String?, profits, filterType: 'profit'),
                _buildInsightList(context, data['summary'] as String?, losses, filterType: 'loss'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsightList(BuildContext context, String? summary, List<dynamic> list, {String? filterType}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filterType == 'profit'
                  ? Icons.trending_up_rounded
                  : filterType == 'loss'
                      ? Icons.trending_down_rounded
                      : Icons.analytics_outlined,
              size: 48,
              color: AppColors.ink5,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              filterType == 'profit'
                  ? 'No profitable trades yet'
                  : filterType == 'loss'
                      ? 'No losing trades yet'
                      : 'No trades to review yet',
              style: GoogleFonts.inter(color: AppColors.ink3, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Realized trades will show up here.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink5),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Every trade is a lesson.',
                style: GoogleFonts.inter(
                  color: AppColors.ink,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                summary ?? 'Review these lessons to refine your edge.',
                style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final insight = list[index] as Map<String, dynamic>;
              final isProfit = insight['type'] == 'profit';
              final pnlAmount = (insight['pnl'] as num?)?.toDouble() ?? 0.0;
              
              return Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.pureWhite,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.birch),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${insight['symbol']} • ${insight['market']?.toUpperCase() ?? ''}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isProfit ? AppColors.bullLight : AppColors.bearLight,
                            borderRadius: BorderRadius.circular(AppRadius.tag),
                          ),
                          child: Text(
                            isProfit ? 'PROFIT' : 'LOSS',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isProfit ? AppColors.bull : AppColors.bear,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      insight['reason'] as String? ?? 'Review this trade.',
                      style: GoogleFonts.inter(color: AppColors.ink3, fontSize: 13),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isProfit 
                            ? 'Realized Profit' 
                            : 'Realized Loss',
                          style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12),
                        ),
                        Text(
                          isProfit 
                            ? '+₹${pnlAmount.toStringAsFixed(2)}' 
                            : '-₹${pnlAmount.abs().toStringAsFixed(2)}', 
                          style: GoogleFonts.inter(
                            color: isProfit ? AppColors.bull : AppColors.bear, 
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: isProfit 
                            ? AppColors.bullLight.withValues(alpha: 0.15) 
                            : AppColors.bearLight.withValues(alpha: 0.15), 
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LESSON & ADVICE',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isProfit ? AppColors.bull : AppColors.bear,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            insight['advice'] as String? ?? 'Stay patient and respect risk.',
                            style: GoogleFonts.inter(
                              color: AppColors.ink2,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
