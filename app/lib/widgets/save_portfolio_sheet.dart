import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../screens/main/convert_account_screen.dart';
import '../services/analytics_service.dart';
import 'auth_kit.dart';

/// Asks a guest to keep what they've built ("save your portfolio") instead of
/// asking them to "sign up". Completes when the sheet closes, either way.
Future<void> showSavePortfolioSheet(BuildContext context, {required String trigger}) async {
  AnalyticsService.log('save_portfolio_prompt', {'trigger': trigger});
  final save = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('DON’T LOSE YOUR PROGRESS', style: AppText.sectionLabel.copyWith(color: AppColors.titanGold)),
          const SizedBox(height: AppSpacing.sm),
          Text('Save your portfolio',
              style: AppFonts.sans(size: 26, weight: FontWeight.w700, color: AppColors.ink, height: 1.15)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You’re trading as a guest, so your portfolio lives only on this phone. Save it to keep it safe and use it on any device.',
            style: AppFonts.sans(size: 15, color: AppColors.ink3, height: 1.45),
          ),
          const SizedBox(height: AppSpacing.lg),
          AuthPrimaryButton(label: 'Save my portfolio', onPressed: () => Navigator.of(ctx).pop(true)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppColors.ink3, minimumSize: const Size.fromHeight(44)),
            child: const Text('Maybe later'),
          ),
        ]),
      ),
    ),
  );
  AnalyticsService.log('save_portfolio_choice', {'trigger': trigger, 'save': save == true ? 1 : 0});
  if (save == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConvertAccountScreen()));
  }
}
