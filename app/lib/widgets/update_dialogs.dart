import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../services/churn_telemetry_service.dart';

class MaintenanceScreen extends StatelessWidget {
  /// Default copy shown when no maintenance message is configured (R10.4, R10.5).
  static const String defaultMessage =
      'We are currently performing system upgrades. We will be back online shortly!';

  final String message;

  const MaintenanceScreen({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkColor = isDark ? AppColors.cream : Palette.dark.card;
    final goldColor = AppColors.titanGold;

    // Self-safe: tolerate an empty/whitespace message by showing the default
    // copy, even though AuthService also substitutes a default (R10.3-R10.5).
    final displayMessage = message.trim().isEmpty ? defaultMessage : message;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: goldColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.construction_rounded,
                  size: 80,
                  color: goldColor,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Under Maintenance',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: inkColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                displayMessage,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppColors.ink4 : AppColors.ink4,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(goldColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Release-note lines as the update prompts show them: blank lines dropped and
/// any leading bullet glyph stripped, so `docs/release-notes.md` copy pasted
/// with or without "•" renders the same.
List<String> parseReleaseNotes(String notes) => notes
    .split('\n')
    .map((l) => l.trim().replaceFirst(RegExp(r'^[•\-\*·]\s*'), ''))
    .where((l) => l.isNotEmpty)
    .toList();

/// Opens the store link. `true` only on a successful launch; an unparseable
/// url, `launchUrl` returning false, or a thrown error all yield `false` so the
/// caller keeps the prompt up and says so.
Future<bool> _openStore(String url) async {
  final uri = Uri.tryParse(url);
  // Uri.tryParse('') is an empty Uri, not null; a schemeless link can't open a store.
  if (uri == null || !uri.hasScheme) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

void _showStoreError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Couldn\'t open the store. Please try again.')),
  );
}

/// Brand-blue header shared by both update prompts: icon tile, eyebrow, title
/// and a "v2.0.4 → v2.0.5" chip. Either version may be empty (first fetch not
/// back yet, or PackageInfo unreadable); the chip shrinks to what is known.
class _UpdateHero extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String currentVersion;
  final String latestVersion;
  final BorderRadius radius;

  const _UpdateHero({
    required this.eyebrow,
    required this.title,
    required this.currentVersion,
    required this.latestVersion,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    const onBrand = Colors.white;
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.goldDeep, AppColors.imperialGold, AppColors.goldMid],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Two soft rings for depth; purely decorative.
          Positioned(right: -36, top: -36, child: _ring(140)),
          Positioned(right: 40, bottom: -50, child: _ring(96)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: onBrand.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: onBrand.withValues(alpha: 0.22)),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: onBrand, size: 26),
                ),
                const SizedBox(height: 18),
                Text(
                  eyebrow.toUpperCase(),
                  style: AppFonts.mono(
                    size: 11,
                    weight: FontWeight.w600,
                    color: onBrand.withValues(alpha: 0.78),
                    spacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: onBrand, height: 1.2),
                ),
                if (latestVersion.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _versionChip(onBrand),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionChip(Color onBrand) {
    final dim = AppFonts.mono(size: 12, weight: FontWeight.w500, color: onBrand.withValues(alpha: 0.7));
    final bright = AppFonts.mono(size: 12, weight: FontWeight.w700, color: onBrand);
    final showFrom = currentVersion.isNotEmpty && currentVersion != latestVersion;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: onBrand.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showFrom) ...[
            Text('v$currentVersion', style: dim),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward_rounded, size: 14, color: onBrand.withValues(alpha: 0.7)),
            ),
          ],
          Text('v$latestVersion', style: bright),
        ],
      ),
    );
  }

  Widget _ring(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 18),
        ),
      );
}

/// "What's new" card: one checked row per release-note line. A short leading
/// label such as "New:" is lifted into a tag so headline features stand out.
class _ReleaseNotesCard extends StatelessWidget {
  final List<String> lines;
  final double? maxHeight;

  const _ReleaseNotesCard({required this.lines, this.maxHeight});

  static final _tagPattern = RegExp(r'^([A-Za-z]{2,10}):\s+(.+)$');

  @override
  Widget build(BuildContext context) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final l in lines) _row(l)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WHAT\'S NEW', style: AppText.sectionLabel),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.birch),
          ),
          child: maxHeight == null
              ? list
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight!),
                  child: SingleChildScrollView(child: list),
                ),
        ),
      ],
    );
  }

  Widget _row(String line) {
    final m = _tagPattern.firstMatch(line);
    final tag = m?.group(1);
    final text = m?.group(2) ?? line;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: AppColors.bullLight, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 13, color: AppColors.bull),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (tag != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: AppCard.badge(AppColors.goldPale),
                      child: Text(tag.toUpperCase(), style: AppText.badge.copyWith(color: AppColors.goldMid)),
                    ),
                  ),
                TextSpan(text: text),
              ]),
              style: AppFonts.sans(size: 13.5, color: AppColors.ink2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width primary button with a spinner while the store is opening, plus
/// the reassurance line under it.
class _UpdateActions extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;

  const _UpdateActions({required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: busy ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.imperialGold,
              disabledBackgroundColor: AppColors.imperialGold.withValues(alpha: 0.7),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.system_update_alt_rounded, size: 20),
                      const SizedBox(width: 10),
                      Text('Update now', style: AppText.button.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined, size: 14, color: AppColors.ink5),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Free on Google Play · your portfolio stays as it is',
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(color: AppColors.ink5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Non-dismissible wrapper around [HardUpdateScreen] that blocks the Android
/// back gesture/button so the user cannot leave the gate (R8.4, R8.7).
class HardUpdateGate extends StatelessWidget {
  final String updateUrl;
  final String releaseNotes;
  final String latestVersion;
  final String currentVersion;

  const HardUpdateGate({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    this.latestVersion = '',
    this.currentVersion = '',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: HardUpdateScreen(
        updateUrl: updateUrl,
        releaseNotes: releaseNotes,
        latestVersion: latestVersion,
        currentVersion: currentVersion,
      ),
    );
  }
}

class HardUpdateScreen extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;
  final String latestVersion;
  final String currentVersion;

  const HardUpdateScreen({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    this.latestVersion = '',
    this.currentVersion = '',
  });

  @override
  State<HardUpdateScreen> createState() => _HardUpdateScreenState();
}

class _HardUpdateScreenState extends State<HardUpdateScreen> {
  bool _busy = false;

  /// Attempts to open the store. On failure the gate is kept and an error is
  /// shown; the gate is never dismissed by this control (R8.5, R8.6).
  Future<void> _launchUpdate() async {
    setState(() => _busy = true);
    final launched = await _openStore(widget.updateUrl);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!launched) _showStoreError(context);
  }

  @override
  Widget build(BuildContext context) {
    final notes = parseReleaseNotes(widget.releaseNotes);
    final version = widget.latestVersion.isEmpty ? 'This version' : 'Version ${widget.latestVersion}';

    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          _UpdateHero(
                            eyebrow: 'Update required',
                            title: 'Update to keep trading',
                            currentVersion: widget.currentVersion,
                            latestVersion: widget.latestVersion,
                            radius: BorderRadius.circular(AppRadius.xl + 4),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '$version is needed to continue. It brings new '
                            'markets, fixes and a smoother app. It takes under a minute.',
                            style: AppFonts.sans(size: 15, color: AppColors.ink3, height: 1.5),
                          ),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _ReleaseNotesCard(lines: notes),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _UpdateActions(busy: _busy, onPressed: _launchUpdate),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The in-app update prompt shown over the home screen when
/// `min_supported_version <= installed < latest_version`.
///
/// Kept blocking (no back, no barrier tap, no "later"), as it has been since
/// 1.2.11: the only way forward is the store.
class SoftUpdateDialog extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;
  final String latestVersion;
  final String currentVersion;
  final VoidCallback onDismiss;

  const SoftUpdateDialog({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    required this.onDismiss,
    this.latestVersion = '',
    this.currentVersion = '',
  });

  @override
  State<SoftUpdateDialog> createState() => _SoftUpdateDialogState();
}

class _SoftUpdateDialogState extends State<SoftUpdateDialog> {
  bool _busy = false;

  /// Opens the store link. The dialog stays up either way; on failure the
  /// user is told and can try again (R9.4).
  Future<void> _onUpdatePressed() async {
    ChurnTelemetryService.instance.recordButtonTap('global_soft_update_now_btn');
    setState(() => _busy = true);
    final launched = await _openStore(widget.updateUrl);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!launched) _showStoreError(context);
  }

  @override
  Widget build(BuildContext context) {
    final notes = parseReleaseNotes(widget.releaseNotes);
    const radius = AppRadius.xl + 4;

    return PopScope(
      canPop: false,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          backgroundColor: AppColors.pureWhite,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(color: AppColors.birch),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UpdateHero(
                  eyebrow: 'New update',
                  title: 'A better Trading Titans is ready',
                  currentVersion: widget.currentVersion,
                  latestVersion: widget.latestVersion,
                  radius: BorderRadius.zero,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Update now to keep trading with the newest markets and fixes.',
                          style: AppFonts.sans(size: 14.5, color: AppColors.ink3, height: 1.5),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _ReleaseNotesCard(lines: notes, maxHeight: 210),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: _UpdateActions(busy: _busy, onPressed: _onUpdatePressed),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks the user to rate the app on the Play Store.
///
/// Deliberately shaped like [SoftUpdateDialog]: two choices, the store launch
/// can fail without losing the dialog, and the "later" branch hands the snooze
/// back to the caller rather than persisting it here.
///
/// Dismissing without choosing (back gesture) records nothing, so the ask
/// simply returns on a later launch instead of burning the snooze window.
class RateAppDialog extends StatefulWidget {
  final String storeUrl;

  /// Called when the store opened successfully. Suppresses all future asks.
  final VoidCallback onRateNow;

  /// Called when the user defers. Starts a fresh snooze window.
  final VoidCallback onRemindLater;

  const RateAppDialog({
    super.key,
    required this.storeUrl,
    required this.onRateNow,
    required this.onRemindLater,
  });

  @override
  State<RateAppDialog> createState() => _RateAppDialogState();
}

class _RateAppDialogState extends State<RateAppDialog> {
  /// Opens the store listing. Returns `true` only on a successful launch; an
  /// unparseable url, `launchUrl` returning false, or a thrown error all yield
  /// `false` so the caller keeps the dialog open.
  Future<bool> _launchStore() async {
    final uri = Uri.tryParse(widget.storeUrl);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// On success marks the prompt done and closes. On failure the dialog stays
  /// open with an error, and nothing is recorded — the user has not been given
  /// a chance to rate yet, so they should still be asked later.
  Future<void> _onRateNowPressed() async {
    ChurnTelemetryService.instance.recordButtonTap('global_rate_app_5_stars_btn');
    final launched = await _launchStore();
    if (!mounted) return;
    if (launched) {
      widget.onRateNow();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t open the store. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkColor = isDark ? AppColors.cream : Palette.dark.card;
    final bodyColor =
        isDark ? AppColors.ink4 : AppColors.ink4;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? Palette.dark.card : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded,
                    color: AppColors.imperialGold, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enjoying Trading Titans?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: inkColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'A rating on the Play Store helps other traders find the app. '
              'It only takes a moment.',
              style: TextStyle(fontSize: 14, color: bodyColor, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ChurnTelemetryService.instance.recordButtonTap('global_rate_app_remind_later_btn');
                    widget.onRemindLater();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Remind me later',
                    style: TextStyle(
                      color: bodyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _onRateNowPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.imperialGold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Rate now',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
