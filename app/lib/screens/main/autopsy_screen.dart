import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import '../../models/order.dart';

class AutopsyScreen extends StatelessWidget {
  const AutopsyScreen({super.key});

  Order? _findMatchingOrder(List<Order> orders, String symbol, double pnl) {
    for (final o in orders) {
      if (o.symbol == symbol && (o.realizedPnl - pnl).abs() < 0.05) {
        return o;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        SupabaseService().getAutopsy(),
        SupabaseService().getOrders(),
      ]),
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

        final results = snapshot.data ?? [{}, <Order>[]];
        final data = (results[0] as Map<String, dynamic>?) ?? {};
        final orders = (results[1] as List<Order>?) ?? [];
        
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
                _buildInsightList(context, data['summary'] as String?, insights, orders),
                _buildInsightList(context, data['summary'] as String?, profits, orders, filterType: 'profit'),
                _buildInsightList(context, data['summary'] as String?, losses, orders, filterType: 'loss'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsightList(BuildContext context, String? summary, List<dynamic> list, List<Order> orders, {String? filterType}) {
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
              final matchedOrder = _findMatchingOrder(orders, insight['symbol'] as String? ?? '', pnlAmount);
              
              // Populate charges from API if present, otherwise fall back to matching local order record
              final totalCharges = (insight['total_charges'] as num?)?.toDouble() ?? (matchedOrder?.totalCharges ?? 0.0);
              
              // Put totalCharges back into the insight map so the Builder down the line can retrieve it!
              insight['total_charges'] = totalCharges;
              
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
                    Builder(
                      builder: (context) {
                        final totalCharges = (insight['total_charges'] as num?)?.toDouble() ?? 0.0;
                        final netPnl = pnlAmount - totalCharges;
                        final isNetProfit = netPnl > 0;
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  isProfit ? 'Gross Realized Profit' : 'Gross Realized Loss',
                                  style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12),
                                ),
                                Text(
                                  isProfit 
                                    ? '+₹${pnlAmount.toStringAsFixed(2)}' 
                                    : '-₹${pnlAmount.abs().toStringAsFixed(2)}', 
                                  style: GoogleFonts.inter(
                                    color: isProfit ? AppColors.bull : AppColors.bear, 
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  )
                                ),
                              ],
                            ),
                            if (totalCharges > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Transaction Charges ',
                                        style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.birch.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'DEMO ONLY',
                                          style: GoogleFonts.inter(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.ink4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '-₹${totalCharges.toStringAsFixed(2)}',
                                    style: GoogleFonts.inter(
                                      color: AppColors.bear,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Divider(color: AppColors.birch, height: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isNetProfit ? 'Net Realized Profit' : 'Net Realized Loss',
                                    style: GoogleFonts.inter(color: AppColors.ink, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    isNetProfit 
                                      ? '+₹${netPnl.toStringAsFixed(2)}' 
                                      : '-₹${netPnl.abs().toStringAsFixed(2)}', 
                                    style: GoogleFonts.inter(
                                      color: isNetProfit ? AppColors.bull : AppColors.bear, 
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    )
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isNetProfit 
                                      ? AppColors.bullLight.withValues(alpha: 0.15) 
                                      : AppColors.bearLight.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isNetProfit 
                                        ? AppColors.bull.withValues(alpha: 0.2) 
                                        : AppColors.bear.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isNetProfit ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                      color: isNetProfit ? AppColors.bull : AppColors.bear,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        pnlAmount > 0
                                            ? 'Charges reduced your return by ${((totalCharges / pnlAmount) * 100).toStringAsFixed(1)}% (Deducted from virtual cash).'
                                            : 'Charges increased this loss by ₹${totalCharges.toStringAsFixed(2)} (Deducted from virtual cash).',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isNetProfit ? AppColors.bull : AppColors.bear,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
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
