import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';
import 'package:google_fonts/google_fonts.dart';

class CompeteScreen extends StatefulWidget {
  const CompeteScreen({super.key});

  @override
  State<CompeteScreen> createState() => _CompeteScreenState();
}

class _CompeteScreenState extends State<CompeteScreen> {
  final SupabaseService _supabase = SupabaseService();

  Future<List<Map<String, dynamic>>> _getLeaderboard() async {
    final user = _supabase.currentUser;
    final userId = user?.id;
    final rows = await _supabase.getLeaderboard();
    return rows.map((row) {
      row['is_self'] = row['user_id'] == userId;
      return row;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly League'),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getLeaderboard(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load leaderboard: ${snapshot.error}'));
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Center(child: Text('No traders on the leaderboard yet.', style: TextStyle(color: AppColors.ink4)));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text('Best realised P&L wins. New week resets every Monday.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
                const SizedBox(height: AppSpacing.lg),
                ...rows.take(3).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;
                  final podiumColors = [AppColors.goldDeep, const Color(0xFFA8A8A8), const Color(0xFFCD7F32)];
                  final podiumLabels = ['🥇', '🥈', '🥉'];
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: podiumColors[index], width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Text(podiumLabels[index], style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row['name'] ?? 'Titan',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
                              const SizedBox(height: 4),
                              Text('₹${(row['realized_pnl'] as num?)?.toStringAsFixed(0) ?? '0'}',
                                  style: GoogleFonts.inter(color: AppColors.bull, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: podiumColors[index].withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.tag),
                          ),
                          child: Text(row['plan'] ?? 'Free',
                              style: TextStyle(color: podiumColors[index], fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                }),
                ...rows.skip(3).toList().asMap().entries.map((entry) {
                  final index = entry.key + 4;
                  final row = entry.value;
                  final isSelf = row['is_self'] == true;
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: isSelf ? AppColors.goldPale.withValues(alpha: 0.15) : AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: isSelf ? AppColors.goldBorder : AppColors.birch),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.goldPale,
                          child: Text('$index',
                              style: GoogleFonts.inter(color: AppColors.goldDeep, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      row['name'] ?? 'Titan',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.imperialGold,
                                        borderRadius: BorderRadius.circular(AppRadius.tag),
                                      ),
                                      child: const Text('You',
                                          style: TextStyle(color: AppColors.pureWhite, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('₹${(row['realized_pnl'] as num?)?.toStringAsFixed(0) ?? '0'} P&L',
                                  style: GoogleFonts.inter(
                                    color: ((row['realized_pnl'] as num?)?.toDouble() ?? 0) >= 0
                                        ? AppColors.bull
                                        : AppColors.bear,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.goldPale,
                            borderRadius: BorderRadius.circular(AppRadius.tag),
                          ),
                          child: Text(row['plan'] ?? 'Free',
                              style: GoogleFonts.inter(color: AppColors.goldDeep, fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
