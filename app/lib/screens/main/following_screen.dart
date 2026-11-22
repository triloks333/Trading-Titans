import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../services/plan_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/trader_sheet.dart';
import '../../widgets/upgrade_sheet.dart';
import 'notifications_screen.dart' show noticeAge;

/// Follow top traders (Pro): recent trades from the people you follow, who you
/// follow, and your own "let Pro members follow me" switch.
class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  final _api = SupabaseService();
  bool _loading = true;
  bool _locked = false;
  bool _share = false;
  List<Map<String, dynamic>> _feed = const [];
  List<Map<String, dynamic>> _traders = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final share = await _api.getShareTrades();
      final traders = await _api.getFollowedTraders();
      var feed = const <Map<String, dynamic>>[];
      var locked = false;
      try {
        feed = await _api.getFollowedFeed();
      } catch (e) {
        if (PlanLimitException.from(e) == null) rethrow;
        locked = true;
      }
      if (!mounted) return;
      setState(() {
        _share = share;
        _traders = traders;
        _feed = feed;
        _locked = locked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "We couldn't load this. Check your connection and try again.";
        _loading = false;
      });
    }
  }

  Future<void> _setShare(bool on) async {
    setState(() => _share = on);
    try {
      await _api.setShareTrades(on);
    } catch (_) {
      if (!mounted) return;
      setState(() => _share = !on);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                10,
                AppSpacing.lg,
                10,
              ),
              child: Row(
                children: [
                  AuthIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Following',
                      style: AppFonts.sans(
                        size: 20,
                        weight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(_error!, style: AppText.body),
                            ),
                          _shareCard(),
                          const SizedBox(height: 16),
                          if (_locked)
                            const LockedFeatureCard(
                              title: 'Follow the best traders',
                              message:
                                  'Pro lets you follow up to 20 traders from the league, see their trades and get a push when they trade.',
                              source: 'following',
                            )
                          else ...[
                            Text(
                              'PEOPLE YOU FOLLOW',
                              style: AppText.sectionLabel,
                            ),
                            const SizedBox(height: 8),
                            if (_traders.isEmpty)
                              Text(
                                'Tap a name on the Weekly League or Pro League to follow them.',
                                style: AppText.bodySmall,
                              )
                            else
                              for (final t in _traders) _traderRow(t),
                            const SizedBox(height: 18),
                            Text(
                              'THEIR RECENT TRADES',
                              style: AppText.sectionLabel,
                            ),
                            const SizedBox(height: 8),
                            if (_feed.isEmpty)
                              Text(
                                'No trades in the last 14 days from people you follow.',
                                style: AppText.bodySmall,
                              )
                            else
                              for (final f in _feed) _feedRow(f),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            'Practice trades with virtual money. Shown for learning only, not as advice to copy.',
                            style: AppFonts.sans(
                              size: 11,
                              color: AppColors.ink4,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareCard() => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    decoration: BoxDecoration(
      color: AppColors.pureWhite,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.birch),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Let Pro members follow my trades', style: AppText.bodyBold),
              Text(
                'They see what you traded and your % result, never your quantities or balance.',
                style: AppFonts.sans(size: 12, color: AppColors.ink4),
              ),
            ],
          ),
        ),
        Switch(value: _share, onChanged: _setShare),
      ],
    ),
  );

  Widget _traderRow(Map<String, dynamic> t) {
    final pnl = (t['pnl_7d'] as num?)?.toDouble() ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () async {
        await showTraderSheet(context, t['trader_id'] as String);
        _load();
      },
      title: Text(
        (t['name'] as String? ?? '').trim().isEmpty
            ? 'Titan'
            : t['name'] as String,
        style: AppText.bodyBold,
      ),
      subtitle: Text(
        t['shares_trades'] == true
            ? '${t['trades_7d']} trades this week'
            : 'Stopped sharing trades',
        style: AppFonts.sans(size: 12, color: AppColors.ink4),
      ),
      trailing: Text(
        Money.signedWallet(pnl, decimals: 0),
        style: AppFonts.mono(
          size: 13,
          weight: FontWeight.w600,
          color: pnl >= 0 ? AppColors.bull : AppColors.bear,
        ),
      ),
    );
  }

  Widget _feedRow(Map<String, dynamic> f) {
    final buy = f['side'] == 'buy';
    final pct = (f['pnl_pct'] as num?)?.toDouble();
    final what = f['instrument_type'] == 'OPTION'
        ? '${f['symbol']} ${(f['strike_price'] as num?)?.toStringAsFixed(0) ?? ''} ${f['option_type'] ?? ''}'
        : '${f['symbol']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.birch),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: AppCard.badge(
              buy ? AppColors.bullLight : AppColors.bearLight,
            ),
            child: Text(
              buy ? 'BUY' : 'SELL',
              style: AppFonts.sans(
                size: 10,
                weight: FontWeight.w700,
                color: buy ? AppColors.bull : AppColors.bear,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  what,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyBold,
                ),
                Text(
                  '${f['trader_name'] ?? 'Trader'} · ${noticeAge(f['executed_at'] as String?)}',
                  style: AppFonts.sans(size: 12, color: AppColors.ink4),
                ),
              ],
            ),
          ),
          if (pct != null)
            Text(
              '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
              style: AppFonts.mono(
                size: 13,
                weight: FontWeight.w600,
                color: pct >= 0 ? AppColors.bull : AppColors.bear,
              ),
            ),
        ],
      ),
    );
  }
}
