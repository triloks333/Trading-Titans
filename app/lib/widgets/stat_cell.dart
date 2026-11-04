import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// A vertical label-over-value cell used inside summary/stat rows (e.g. the
/// portfolio summary card and holding/position cards). Extracted from the
/// previously-duplicated `_holdingStat` / `_summaryCardItem` builders so the
/// layout lives in one place; callers tune sizes/weights/colors via params.
class StatCell extends StatelessWidget {
  final String label;
  final String value;
  final double labelSize;
  final FontWeight? labelWeight;
  final double gap;
  final double valueSize;
  final FontWeight valueWeight;

  /// Explicit value color (e.g. green/red P&L). Falls back to
  /// [defaultValueColor] when null.
  final Color? valueColor;

  /// Value color when [valueColor] is null. Defaults to `AppColors.ink2`.
  final Color? defaultValueColor;

  /// Whether to wrap in [Expanded] (cells laid out in a Row). Defaults to true.
  final bool expanded;

  const StatCell({
    super.key,
    required this.label,
    required this.value,
    this.labelSize = 10,
    this.labelWeight,
    this.gap = 1,
    this.valueSize = 12,
    this.valueWeight = FontWeight.w600,
    this.valueColor,
    this.defaultValueColor,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: labelSize,
            color: AppColors.ink4,
            fontWeight: labelWeight,
          ),
        ),
        SizedBox(height: gap),
        Text(
          value,
          style: GoogleFonts.ibmPlexSans(
            fontSize: valueSize,
            fontWeight: valueWeight,
            color: valueColor ?? defaultValueColor ?? AppColors.ink2,
          ),
        ),
      ],
    );
    return expanded ? Expanded(child: column) : column;
  }
}
