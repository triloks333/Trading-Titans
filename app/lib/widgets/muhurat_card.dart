import 'dart:async';

import 'package:flutter/material.dart';

import '../core/market_hours.dart';
import '../core/theme.dart';
import '../screens/main/muhurat_screen.dart';
import '../services/churn_telemetry_service.dart';

/// Home card for the next special session (Diwali Muhurat). Renders nothing until
/// a row exists in `market_special_sessions`, and hides itself once it ends.
class MuhuratCard extends StatefulWidget {
  const MuhuratCard({super.key});

  @override
  State<MuhuratCard> createState() => _MuhuratCardState();
}

class _MuhuratCardState extends State<MuhuratCard> {
  late final Timer _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final s = MarketHours.nextSpecialSession(now);
    if (s == null) return const SizedBox.shrink();
    final live = !now.isBefore(s.start);
    final gold = AppColors.titanGold;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 10),
      child: Material(
        color: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: gold)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () {
            ChurnTelemetryService.instance.recordButtonTap('home_muhurat_special_card_btn');
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MuhuratScreen()));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.local_fire_department_rounded, size: 40, color: gold),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.name} · ${istLabel(s.start, 'EEE d MMM')}', style: AppText.bodyBold),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(style: AppText.bodySmall, children: [
                    TextSpan(text: live ? 'Live now · ends in ' : 'Starts in '),
                    TextSpan(
                        text: countdownLabel((live ? s.end : s.start).difference(now)),
                        style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: gold)),
                    if (!live) const TextSpan(text: ' · Muhurat League & reward'),
                  ]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
            ]),
          ),
        ),
      ),
    );
  }
}
