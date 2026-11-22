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

/// The 7-day Pro pass offer shown when a free user opens the app.
///
/// First week ₹1 for an account that has never paid; after that the same week is
/// ₹29. Shown at most once a day, so it stays an offer rather than a nag. Never on
/// iOS (Apple requires StoreKit for digital goods) and never with monetisation off.
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

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(_prefKey) == today) return;
    await prefs.setString(_prefKey, today);
    if (!context.mounted) return;

    final trial = plan.trialEligible;
    ChurnTelemetryService.instance.recordPaywallStep(
      trial ? 'pass_offer_trial_shown' : 'pass_offer_week_shown',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ProPassOfferDialog(trial: trial, onStart: () => openPlans(context, sku: trial ? 'pro_trial_week' : 'pro_week')),
    );
  }
}

class _ProPassOfferDialog extends StatelessWidget {
  const _ProPassOfferDialog({required this.trial, required this.onStart});

  final bool trial;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final price = trial ? '₹1' : '₹29';
    return Dialog(
      backgroundColor: AppColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: AppCard.badge(AppColors.titanGoldSoft),
                child: Text(
                  trial ? 'YOUR FIRST WEEK' : '7-DAY PASS',
                  style: AppFonts.sans(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.titanGold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              trial
                  ? 'Try Pro for 7 days at just ₹1'
                  : 'Get Pro for 7 days at ₹29',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                size: 20,
                weight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              trial
                  ? 'One rupee unlocks everything in Pro for a week. After your first week, the 7-day pass is ₹29.'
                  : 'Unlock everything in Pro for a week. No auto-renewal.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                size: 13.5,
                color: AppColors.ink3,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            for (final f in const [
              '25 F&O trades a month instead of 3',
              'Unlimited trade autopsies and What-If',
              'Full P&L history and every chart range',
              'Unlimited price alerts and watchlists',
              'Weekly coach report and the Pro league',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.bull,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f,
                        style: AppFonts.sans(size: 13.5, color: AppColors.ink2),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.titanGold,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () {
                ChurnTelemetryService.instance.recordButtonTap(
                  trial ? 'pass_offer_trial_cta' : 'pass_offer_week_cta',
                );
                Navigator.of(context).pop();
                onStart();
              },
              child: Text(
                'Start Pro for $price',
                style: AppFonts.sans(
                  size: 15,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ChurnTelemetryService.instance.recordButtonTap(
                  'pass_offer_dismiss',
                );
                Navigator.of(context).pop();
              },
              child: Text(
                'Maybe later',
                style: AppFonts.sans(size: 14, color: AppColors.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
