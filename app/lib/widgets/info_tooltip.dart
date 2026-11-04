import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/glossary.dart';
import '../screens/main/glossary_screen.dart';

/// A small tappable "?" icon placed next to a jargon term. Tapping it shows a
/// plain-English definition + example in a bottom sheet, with a shortcut to the
/// full glossary. No-ops gracefully if the term is unknown.
class InfoTooltip extends StatelessWidget {
  final String term;
  final double size;

  const InfoTooltip({super.key, required this.term, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTermSheet(context, term),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          Icons.help_outline_rounded,
          size: size,
          color: AppColors.ink4,
        ),
      ),
    );
  }
}

/// A label (e.g. "Margin") rendered with a dotted-style hint and a trailing
/// "?" so the whole thing is tappable to reveal its definition.
class TermLabel extends StatelessWidget {
  final String term;
  final String? label;
  final TextStyle? style;

  const TermLabel({super.key, required this.term, this.label, this.style});

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ??
        GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink3);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTermSheet(context, term),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label ?? term, style: baseStyle),
          const SizedBox(width: 3),
          Icon(Icons.help_outline_rounded, size: 14, color: AppColors.ink4),
        ],
      ),
    );
  }
}

/// Shows the definition bottom sheet for [term]. Safe to call with any string;
/// unknown terms simply open the full glossary instead.
void showTermSheet(BuildContext context, String term) {
  final entry = Glossary.of(term);
  if (entry == null) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GlossaryScreen()),
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.xl),
            topRight: Radius.circular(AppRadius.xl),
          ),
          border: Border.all(color: AppColors.birch),
        ),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.birch,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Icon(Icons.school_rounded, size: 20, color: AppColors.imperialGold),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.term,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              entry.definition,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                height: 1.5,
                color: AppColors.ink2,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.birch),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 18, color: AppColors.goldDeep),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      entry.example,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GlossaryScreen()),
                  );
                },
                child: Text(
                  'View all trading terms',
                  style: GoogleFonts.ibmPlexSans(
                    color: AppColors.imperialGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
