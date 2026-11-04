import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/legal.dart';
import '../core/theme.dart';
import 'legal_sheet.dart';

/// Mandatory "I accept the Terms & Conditions and Privacy Policy" checkbox.
///
/// Lives in one widget used by BOTH auth screens because an account can be
/// created from either of them — email/password and Google on the sign-up screen,
/// Google and Guest on the sign-in screen. A checkbox added to only the sign-up
/// screen would be bypassable in two taps, so the wording and behaviour have to
/// be identical in both places rather than copy-pasted and left to drift.
///
/// The links open the real documents through [showLegalSheet], the same renderer
/// Profile already uses, so there is one copy of each policy in the app.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.showError = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Highlights the row after the user tried to continue without accepting.
  final bool showError;

  /// Copy used both on screen and as the accessibility label, so a screen-reader
  /// user hears the same sentence a sighted user reads.
  static const String label =
      'I accept the Terms & Conditions and Privacy Policy';

  /// Shown when a gated action is attempted without acceptance.
  static const String errorText =
      'Please accept the Terms & Conditions and Privacy Policy to continue.';

  @override
  Widget build(BuildContext context) {
    final linkStyle = GoogleFonts.ibmPlexSans(
      fontSize: 13,
      height: 1.4,
      color: AppColors.imperialGold,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.imperialGold,
    );
    final bodyStyle = GoogleFonts.ibmPlexSans(
      fontSize: 13,
      height: 1.4,
      color: AppColors.ink2,
      fontWeight: FontWeight.w500,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Semantics wraps the whole row and carries the checkbox state, so the
        // control is announced as one labelled checkbox rather than an unlabelled
        // box followed by loose text. excludeSemantics stops the inner Text
        // fragments being read out again as separate nodes.
        Semantics(
          container: true,
          checked: value,
          label: label,
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    activeColor: AppColors.imperialGold,
                    side: BorderSide(
                      color: showError ? AppColors.bear : AppColors.birch,
                      width: showError ? 2 : 1,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  // Aligns the first line of text with the checkbox rather than
                  // sitting a couple of pixels high against a 24px box.
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(
                        style: bodyStyle,
                        children: [
                          const TextSpan(text: 'I accept the '),
                          _link(context, 'Terms & Conditions', LegalDocs.terms, linkStyle),
                          const TextSpan(text: ' and '),
                          _link(context, 'Privacy Policy', LegalDocs.privacy, linkStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            errorText,
            style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.bear),
          ),
        ],
      ],
    );
  }

  /// A tappable policy name.
  ///
  /// ponytail: a `TextSpan` recogniser rather than separate buttons, so the
  /// sentence wraps as one paragraph. The ceiling is the tap target — an inline
  /// span is the height of the text, under the 48dp guideline. Accepted here
  /// because the same documents are reachable from Profile with a full-size row,
  /// so this is a shortcut and not the only route to them.
  TextSpan _link(
    BuildContext context,
    String text,
    LegalDoc doc,
    TextStyle style,
  ) {
    return TextSpan(
      text: text,
      style: style,
      recognizer: TapGestureRecognizer()..onTap = () => showLegalSheet(context, doc),
      semanticsLabel: '$text, opens in a sheet',
    );
  }
}

/// The virtual-money / not-a-broker / delayed-data disclaimer.
///
/// Sits at the very foot of the auth screens, visually separate from the consent
/// checkbox: the checkbox is a control the user must act on, this is standing
/// context they should read. Full width and centre-aligned so it lines up with
/// the card above it rather than looking like a stray paragraph.
class AuthDisclaimer extends StatelessWidget {
  const AuthDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.bear.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.bear.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AppColors.bear),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'VIRTUAL TRADING ONLY',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.bear,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            LegalDocs.authDisclaimer,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              height: 1.5,
              color: AppColors.ink4,
            ),
          ),
        ],
      ),
    );
  }
}
