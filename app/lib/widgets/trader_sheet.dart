import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/churn_telemetry_service.dart';
import '../services/supabase_service.dart';
import 'upgrade_sheet.dart';

/// Bottom sheet for a trader tapped on the league: their 30-day record and a
/// Follow button (Pro). Following is only possible when they share their trades.
Future<void> showTraderSheet(BuildContext context, String traderId) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.pureWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TraderSheet(traderId: traderId),
  );
}

class _TraderSheet extends StatefulWidget {
  const _TraderSheet({required this.traderId});

  final String traderId;

  @override
  State<_TraderSheet> createState() => _TraderSheetState();
}

class _TraderSheetState extends State<_TraderSheet> {
  Map<String, dynamic>? _p;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SupabaseService().getTraderProfile(widget.traderId);
      if (mounted) setState(() => (_p = p, _loading = false));
    } catch (e) {
      if (mounted)
        setState(
          () => (_error = "Couldn't load this trader.", _loading = false),
        );
    }
  }

  Future<void> _toggle() async {
    final following = _p?['following'] == true;
    setState(() => _busy = true);
    try {
      ChurnTelemetryService.instance.recordButtonTap(
        following ? 'trader_unfollow' : 'trader_follow',
      );
      if (following) {
        await SupabaseService().unfollowTrader(widget.traderId);
      } else {
        await SupabaseService().followTrader(widget.traderId);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (await handlePlanLimitError(context, e, source: 'follow_trader'))
        return;
      if (!mounted) return;
      final msg = '$e'.contains('20 traders')
          ? 'You can follow up to 20 traders. Unfollow someone first.'
          : "Couldn't update. Try again.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: _loading
            ? const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              )
            : p == null
            ? SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    _error ?? 'Trader not found',
                    style: AppText.body,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (p['name'] as String? ?? '').trim().isEmpty
                              ? 'Titan'
                              : p['name'] as String,
                          style: AppFonts.sans(
                            size: 19,
                            weight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (p['tier'] == 'pro' || p['tier'] == 'titan')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: AppCard.badge(
                            p['tier'] == 'titan'
                                ? AppColors.violetLight
                                : AppColors.goldPale,
                          ),
                          child: Text(
                            p['tier'] == 'titan' ? 'TITAN' : 'PRO',
                            style: AppFonts.sans(
                              size: 10,
                              weight: FontWeight.w700,
                              color: p['tier'] == 'titan'
                                  ? AppColors.violet
                                  : AppColors.goldDeep,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _stat('Closed trades (30d)', '${p['trades_30d'] ?? 0}'),
                      _stat(
                        'Win rate (30d)',
                        p['win_rate_30d'] == null
                            ? '—'
                            : '${p['win_rate_30d']}%',
                      ),
                      _stat('Followers', '${p['followers'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (p['is_me'] == true)
                    Text(
                      'This is you. Turn on "Let Pro members follow my trades" in Following to be followable.',
                      style: AppFonts.sans(size: 13, color: AppColors.ink3),
                    )
                  else if (p['shares_trades'] != true && p['following'] != true)
                    Text(
                      "This trader hasn't chosen to share their trades.",
                      style: AppFonts.sans(size: 13, color: AppColors.ink3),
                    )
                  else
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: p['following'] == true
                            ? AppColors.cream
                            : AppColors.titanGold,
                        foregroundColor: p['following'] == true
                            ? AppColors.ink
                            : Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _busy ? null : _toggle,
                      child: Text(
                        p['following'] == true
                            ? 'Following · tap to unfollow'
                            : 'Follow (Pro)',
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Practice trades with virtual money. For learning only, not advice.',
                    textAlign: TextAlign.center,
                    style: AppFonts.sans(size: 11, color: AppColors.ink4),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppFonts.sans(size: 11, color: AppColors.ink3)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppFonts.mono(
            size: 16,
            weight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}
