import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../core/theme.dart';

/// Shows a policy document from [LegalDocs] in a scrollable bottom sheet.
///
/// One renderer for both Terms and Privacy: the two previously had duplicated
/// sheet scaffolding that differed only by title and body string.
void showLegalSheet(BuildContext context, LegalDoc doc) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.pureWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (context) => DraggableScrollableSheet(
      // Taller than the old 0.6 default: these are full policies now, and
      // opening mid-way on a long document buries the first section.
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => _LegalBody(
        doc: doc,
        scrollController: scrollController,
      ),
    ),
  );
}

class _LegalBody extends StatelessWidget {
  const _LegalBody({required this.doc, required this.scrollController});

  final LegalDoc doc;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doc.title,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Last updated: ${doc.lastUpdated}',
            style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink5),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (doc.notice != null) _Notice(doc: doc),
                _paragraph(doc.intro),
                for (final section in doc.sections) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    section.heading,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final p in section.paragraphs) _paragraph(p),
                  for (final b in section.bullets) _Bullet(text: b),
                ],
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                _SupportLink(email: doc.supportEmail),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Text(
          text,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            color: AppColors.ink3,
            height: 1.5,
          ),
        ),
      );
}

/// The red "IMPORTANT NOTICE" block from the website's Terms page. Kept visually
/// distinct because it is the one part a user skimming really should read.
class _Notice extends StatelessWidget {
  const _Notice({required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bear.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border(left: BorderSide(color: AppColors.bear, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.bear),
              const SizedBox(width: AppSpacing.xs),
              Text(
                doc.noticeTitle ?? 'IMPORTANT',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.bear,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            doc.notice!,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: AppColors.ink3,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bullet. A leading `Label:` is bolded, matching the website's `<strong>`
/// lead-ins.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.ibmPlexSans(
      fontSize: 13,
      color: AppColors.ink3,
      height: 1.5,
    );
    // Only treat a short leading fragment as a label, so a mid-sentence colon
    // does not bold half a paragraph.
    final colon = text.indexOf(':');
    final hasLabel = colon > 0 && colon <= 30;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5, right: AppSpacing.sm),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.ink4,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: hasLabel
                ? Text.rich(TextSpan(style: base, children: [
                    TextSpan(
                      text: text.substring(0, colon + 1),
                      style: base.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    TextSpan(text: text.substring(colon + 1)),
                  ]))
                : Text(text, style: base),
          ),
        ],
      ),
    );
  }
}

class _SupportLink extends StatelessWidget {
  const _SupportLink({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Trading Titans Support',
          style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink5),
        ),
        InkWell(
          onTap: () async {
            final uri = Uri(scheme: 'mailto', path: email);
            // Silently ignore a missing mail client rather than throwing: the
            // address is still readable on screen.
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
          child: Text(
            email,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppColors.imperialGold,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
