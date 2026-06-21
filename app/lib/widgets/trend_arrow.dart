import 'package:flutter/material.dart';
import '../core/theme.dart';

/// A small up/down caret used next to gain/loss values so the meaning survives
/// for color-blind users (i.e. it doesn't rely on red/green alone).
class TrendArrow extends StatelessWidget {
  final bool isPositive;
  final double size;
  final Color? color;

  const TrendArrow({
    super.key,
    required this.isPositive,
    this.size = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      isPositive ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
      size: size,
      color: color ?? (isPositive ? AppColors.bull : AppColors.bear),
    );
  }
}
