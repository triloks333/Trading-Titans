import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../screens/main/subscribe_screen.dart';
import '../services/app_flags_service.dart';
import '../services/churn_telemetry_service.dart';
import '../services/plan_service.dart';

/// Opens the plans screen with [sku] preselected.
Future<void> openPlans(BuildContext context, {String? sku}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SubscribeScreen(initialTabIndex: 0, initialSku: sku)),
  );
  await PlanService.instance.refreshUsage();
}

/// The SKU to pitch for a feature: the ₹1 week while the account qualifies, Titan
/// for Titan-only tools, otherwise the ₹29 week.
String pitchSku({bool needsTitan = false}) {
  final plan = PlanService.instance;
  if (needsTitan) return 'titan_monthly';
  if (plan.trialEligible) return 'pro_trial_week';
  return 'pro_week';
}

/// The sheet shown when a free or Pro user reaches something their plan doesn't
/// include. One sheet everywhere, so the pitch and the button never disagree.
Future<void> showUpgradeSheet(
  BuildContext context, {
  required String title,
  required String message,
  bool needsTitan = false,
  String source = 'unknown',
}) async {
  if (!context.read<AppFlagsService>().monetizationEnabled) return;
  ChurnTelemetryService.instance.recordPaywallStep('upgrade_sheet_$source');
  final plan = PlanService.instance;
  final sku = pitchSku(needsTitan: needsTitan);
  final cta = needsTitan
      ? 'See Titan'
      : plan.trialEligible
          ? 'Try Pro for 7 days at ₹1'
          : 'Get Pro for 7 days at ₹29';
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.pureWhite,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: AppColors.titanGoldSoft, shape: BoxShape.circle),
              child: Icon(needsTitan ? Icons.workspace_premium_rounded : Icons.lock_open_rounded, color: AppColors.titanGold, size: 26),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: AppFonts.sans(size: 18, weight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: AppFonts.sans(size: 14, color: AppColors.ink3, height: 1.45)),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.titanGold,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              ChurnTelemetryService.instance.recordButtonTap('upgrade_sheet_cta_$source');
              Navigator.of(ctx).pop();
              openPlans(context, sku: sku);
            },
            child: Text(cta, style: AppFonts.sans(size: 15, weight: FontWeight.w700, color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Not now', style: AppFonts.sans(size: 14, color: AppColors.ink3)),
          ),
        ]),
      ),
    ),
  );
}

/// Shows the upgrade sheet for a server refusal; returns false if [error] wasn't one.
Future<bool> handlePlanLimitError(BuildContext context, Object error, {String source = 'unknown'}) async {
  final e = PlanLimitException.from(error);
  if (e == null) return false;
  final needsTitan = e.feature == PlanFeature.foTrades && PlanService.instance.tier == 'pro';
  await showUpgradeSheet(context, title: 'Plan limit reached', message: e.message, needsTitan: needsTitan, source: source);
  return true;
}

/// A small "2 of 3 left this month" line. Renders nothing when unlimited.
class UsageChip extends StatelessWidget {
  const UsageChip({super.key, required this.feature, required this.noun, this.period = 'this month'});

  final String feature;
  final String noun;
  final String period;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: PlanService.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final plan = PlanService.instance;
    final left = plan.remaining(feature);
    final limit = plan.limitFor(feature);
    if (left == null || limit == null) return const SizedBox.shrink();
    final out = left == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: out ? AppColors.bearLight : AppColors.titanGoldSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(out ? Icons.lock_rounded : Icons.bolt_rounded, size: 14, color: out ? AppColors.bear : AppColors.titanGold),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            out ? 'No free $noun left $period' : '$left of $limit free $noun left $period',
            style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: out ? AppColors.bear : AppColors.ink2),
          ),
        ),
      ]),
    );
  }
}

/// Full-width lock shown in place of a Titan or Pro-only tool.
class LockedFeatureCard extends StatelessWidget {
  const LockedFeatureCard({
    super.key,
    required this.title,
    required this.message,
    this.needsTitan = false,
    this.source = 'locked_card',
  });

  final String title;
  final String message;
  final bool needsTitan;
  final String source;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: PlanService.instance, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final plan = PlanService.instance;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.titanGoldSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.titanGold.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock_rounded, size: 18, color: AppColors.titanGold),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: AppFonts.sans(size: 15, weight: FontWeight.w700, color: AppColors.ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: AppCard.badge(needsTitan ? AppColors.violetLight : AppColors.goldPale),
            child: Text(needsTitan ? 'TITAN' : 'PRO',
                style: AppFonts.sans(size: 10, weight: FontWeight.w700, color: needsTitan ? AppColors.violet : AppColors.goldDeep)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(message, style: AppFonts.sans(size: 13, color: AppColors.ink2, height: 1.45)),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.titanGold, foregroundColor: Colors.white),
          onPressed: () {
            ChurnTelemetryService.instance.recordButtonTap('locked_card_cta_$source');
            openPlans(context, sku: pitchSku(needsTitan: needsTitan));
          },
          child: Text(
            needsTitan ? 'Unlock with Titan' : (plan.trialEligible ? 'Try Pro for ₹1' : 'Unlock with Pro'),
            style: AppFonts.sans(size: 14, weight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}
