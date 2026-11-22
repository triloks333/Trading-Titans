import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../services/app_flags_service.dart';
import '../services/auth_service.dart';
import '../services/churn_telemetry_service.dart';
import '../services/plan_service.dart';
import 'upgrade_sheet.dart';

/// The Pro offer shown when a free user lands in the app after signing in.
///
/// An account that has never paid gets a choice: Pro for 7 days at ₹1, or carry
/// on free and upgrade later at ₹29 for 7 days. Picking free gives up the ₹1 week
/// (recorded on the server). After that, the ₹29 pass is offered at most once a
/// week. Never on iOS (Apple requires StoreKit for digital goods) and never with
/// monetisation off.
class ProPassOffer {
  static const _prefKey = 'tt_pro_pass_offer_last_shown_v1';

  static Future<void> maybeShow(BuildContext context) async {
    if (kIsWeb || Platform.isIOS) return;
    if (!context.read<AppFlagsService>().monetizationEnabled) return;
    final auth = context.read<AuthService>();
    if (auth.isGuest || auth.user == null) return;

    final plan = PlanService.instance;
    await plan.refreshUsage();
    if (!context.mounted || plan.isPaid) return;

    final trial = plan.trialEligible;
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_prefKey) ?? '');
    final now = DateTime.now();
    // The ₹1 choice waits at most a day if they backed out of checkout; the ₹29
    // reminder waits a week.
    final gap = trial ? const Duration(hours: 20) : const Duration(days: 7);
    if (last != null && now.difference(last) < gap) return;
    await prefs.setString(_prefKey, now.toIso8601String());
    if (!context.mounted) return;

    ChurnTelemetryService.instance.recordPaywallStep(trial ? 'pass_offer_trial_shown' : 'pass_offer_week_shown');
    await showDialog<void>(
      context: context,
      barrierDismissible: !trial,
      builder: (ctx) => trial
          ? _TrialChoiceDialog(
              onTrial: () => openPlans(context, sku: 'pro_trial_week'),
              onFree: () => plan.declineTrial(),
            )
          : _WeekPassDialog(onStart: () => openPlans(context, sku: 'pro_week')),
    );
  }
}

const _proPerks = [
  '25 F&O trades a month instead of 3',
  'Unlimited trade autopsies and What-If',
  'Full P&L history and every chart range',
  'Unlimited price alerts and watchlists',
  'Weekly coach report and the Pro League',
];

Widget _badge(String text) => Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: AppCard.badge(AppColors.titanGoldSoft),
        child: Text(text, style: AppFonts.sans(size: 11, weight: FontWeight.w700, color: AppColors.titanGold)),
      ),
    );

Widget _perk(String f, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.check_circle_rounded, size: 17, color: color ?? AppColors.bull),
        const SizedBox(width: 8),
        Expanded(child: Text(f, style: AppFonts.sans(size: 13, color: AppColors.ink2))),
      ]),
    );

/// First week: pick ₹1 Pro or free. No "maybe later": it's a one-time choice.
class _TrialChoiceDialog extends StatelessWidget {
  const _TrialChoiceDialog({required this.onTrial, required this.onFree});

  final VoidCallback onTrial;
  final VoidCallback onFree;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.pureWhite,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _badge('WELCOME OFFER'),
            const SizedBox(height: 12),
            Text('How do you want to start?',
                textAlign: TextAlign.center, style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 16),
            // Option 1: ₹1 week.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.titanGoldSoft,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.titanGold, width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Pro for 7 days', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink))),
                  Text('₹1', style: AppFonts.mono(size: 20, weight: FontWeight.w700, color: AppColors.titanGold)),
                ]),
                const SizedBox(height: 2),
                Text('Only on your first week. No auto-renewal.', style: AppFonts.sans(size: 12, color: AppColors.ink3)),
                const SizedBox(height: 10),
                for (final f in _proPerks) _perk(f),
                const SizedBox(height: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.titanGold,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    ChurnTelemetryService.instance.recordButtonTap('pass_offer_trial_cta');
                    Navigator.of(context).pop();
                    onTrial();
                  },
                  child: Text('Start Pro for ₹1', style: AppFonts.sans(size: 15, weight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            // Option 2: free now, ₹29 later.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.birch),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Continue free', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink))),
                  Text('₹0', style: AppFonts.mono(size: 20, weight: FontWeight.w700, color: AppColors.ink3)),
                ]),
                const SizedBox(height: 8),
                _perk('3 F&O trades a month, 3 autopsies, 1 What-If a day', color: AppColors.ink4),
                _perk('Upgrade any time: Pro is ₹29 for 7 days', color: AppColors.ink4),
                const SizedBox(height: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: () {
                    ChurnTelemetryService.instance.recordButtonTap('pass_offer_trial_free');
                    Navigator.of(context).pop();
                    onFree();
                  },
                  child: Text('Continue free', style: AppFonts.sans(size: 14.5, weight: FontWeight.w600, color: AppColors.ink2)),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Text('Choosing free means the ₹1 week won\'t be offered again.',
                textAlign: TextAlign.center, style: AppFonts.sans(size: 11.5, color: AppColors.ink4)),
          ]),
        ),
      ),
    );
  }
}

/// After the first week: the ₹29 pass, at most once a week.
class _WeekPassDialog extends StatelessWidget {
  const _WeekPassDialog({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _badge('7-DAY PASS'),
          const SizedBox(height: 14),
          Text('Get Pro for 7 days at ₹29',
              textAlign: TextAlign.center, style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text('Unlock everything in Pro for a week. No auto-renewal.',
              textAlign: TextAlign.center, style: AppFonts.sans(size: 13.5, color: AppColors.ink3, height: 1.45)),
          const SizedBox(height: 16),
          for (final f in _proPerks) _perk(f),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.titanGold,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              ChurnTelemetryService.instance.recordButtonTap('pass_offer_week_cta');
              Navigator.of(context).pop();
              onStart();
            },
            child: Text('Start Pro for ₹29', style: AppFonts.sans(size: 15, weight: FontWeight.w700, color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              ChurnTelemetryService.instance.recordButtonTap('pass_offer_dismiss');
              Navigator.of(context).pop();
            },
            child: Text('Maybe later', style: AppFonts.sans(size: 14, color: AppColors.ink3)),
          ),
        ]),
      ),
    );
  }
}
