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

/// Non-dismissible wrapper around [HardUpdateScreen] that blocks the Android
/// back gesture/button so the user cannot leave the gate (R8.4, R8.7).
class HardUpdateGate extends StatelessWidget {
  final String updateUrl;
  final String releaseNotes;
  final String version;

  const HardUpdateGate({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    this.version = '',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: HardUpdateScreen(
        updateUrl: updateUrl,
        releaseNotes: releaseNotes,
        version: version,
      ),
    );
  }
}

/// Opens the store link. Returns `true` only when the launch succeeds; an
/// unparseable url, `launchUrl` returning false, or a thrown error all yield
/// `false` so the caller keeps the prompt up and shows an error (R8.5, R9.4).
Future<bool> _openStore(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
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

/// Release-notes lines with their leading bullet glyphs stripped.
List<String> _noteLines(String notes) => notes
    .split('\n')
    .map((l) => l.trim().replaceFirst(RegExp(r'^[•\-\*·]+\s*'), ''))
    .where((l) => l.isNotEmpty)
    .toList();

class HardUpdateScreen extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;
  final String version;

  const HardUpdateScreen({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    this.version = '',
  });

  @override
  State<HardUpdateScreen> createState() => _HardUpdateScreenState();
}

class _HardUpdateScreenState extends State<HardUpdateScreen> {
  bool _opening = false;

  /// On failure the gate is kept and an error is shown; the gate is never
  /// dismissed by this control (R8.5, R8.6).
  Future<void> _launchUpdate() async {
    setState(() => _opening = true);
    final launched = await _openStore(widget.updateUrl);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!launched) _showStoreError(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    final notes = _noteLines(widget.releaseNotes);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  children: [
                    const _AppBadge(size: 88),
                    const SizedBox(height: 20),
                    if (widget.version.isNotEmpty) ...[
                      _VersionPill(version: widget.version, onHero: false),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      'Time to update',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(size: 26, weight: FontWeight.w700, color: p.ink, spacing: -0.4),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This version of Trading Titans is no longer supported. '
                      'Update to keep trading — your portfolio and progress are safe.',
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(size: 15, color: p.ink3, height: 1.5),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: p.line),
                        ),
                        child: _NotesList(lines: notes),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  _UpdateButton(opening: _opening, onPressed: _launchUpdate),
                  const SizedBox(height: 12),
                  const _StoreCaption(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SoftUpdateDialog extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;
  final VoidCallback onDismiss;
  final String version;

  const SoftUpdateDialog({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    required this.onDismiss,
    this.version = '',
  });

  @override
  State<SoftUpdateDialog> createState() => _SoftUpdateDialogState();
}

class _SoftUpdateDialogState extends State<SoftUpdateDialog> {
  bool _opening = false;

  /// Opens the store link. The dialog stays up since the update is compulsory.
  Future<void> _onUpdatePressed() async {
    ChurnTelemetryService.instance.recordButtonTap('global_soft_update_now_btn');
    setState(() => _opening = true);
    final launched = await _openStore(widget.updateUrl);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!launched) _showStoreError(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    final notes = _noteLines(widget.releaseNotes);
    final maxNotesHeight = MediaQuery.sizeOf(context).height * 0.28;

    return PopScope(
      canPop: false,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          backgroundColor: p.card,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(version: widget.version),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A better Trading Titans is here',
                          style: AppFonts.sans(size: 21, weight: FontWeight.w700, color: p.ink, spacing: -0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Update now to keep trading with the newest features and fixes.',
                          style: AppFonts.sans(size: 14, color: p.ink3, height: 1.45),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxNotesHeight),
                            // Fade the bottom edge so overflowing notes read as scrollable.
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (r) => const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black, Colors.black, Colors.transparent],
                                stops: [0, 0.82, 1],
                              ).createShader(r),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _NotesList(lines: notes),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  child: Column(
                    children: [
                      _UpdateButton(opening: _opening, onPressed: _onUpdatePressed),
                      const SizedBox(height: 12),
                      const _StoreCaption(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient header of the soft-update dialog: the app badge over soft rings.
class _Hero extends StatelessWidget {
  final String version;
  const _Hero({required this.version});

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    return Container(
      height: 168,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.actionDeep, p.action, const Color(0xFF6366F1)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: -50, right: -40, child: _ring(160, 0.10)),
          Positioned(bottom: -70, left: -30, child: _ring(190, 0.08)),
          Positioned(top: 22, left: 30, child: _dot(6)),
          Positioned(bottom: 34, right: 44, child: _dot(4)),
          Positioned(top: 40, right: 70, child: _dot(3)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AppBadge(size: 72),
              if (version.isNotEmpty) ...[
                const SizedBox(height: 14),
                _VersionPill(version: version, onHero: true),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Widget _ring(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );

  static Widget _dot(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      );
}

/// The app logo on a white rounded tile, falling back to an icon if the asset
/// cannot load.
class _AppBadge extends StatelessWidget {
  final double size;
  const _AppBadge({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: AppColors.isDark ? 0.22 : 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Image.asset(
        'assets/logo/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.rocket_launch_rounded, size: size * 0.5, color: const Color(0xFF1E63D6)),
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  final String version;

  /// True on the gradient hero (white on glass), false on a plain surface.
  final bool onHero;
  const _VersionPill({required this.version, required this.onHero});

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    final fg = onHero ? Colors.white : p.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: onHero ? Colors.white.withValues(alpha: 0.18) : p.accentSoft,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: onHero ? Colors.white.withValues(alpha: 0.35) : p.accentLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            'VERSION $version',
            style: AppFonts.mono(size: 11, weight: FontWeight.w600, color: fg, spacing: 0.8),
          ),
        ],
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  final List<String> lines;
  const _NotesList({required this.lines});

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("WHAT'S NEW", style: AppFonts.sans(size: 11, weight: FontWeight.w700, color: p.ink4, spacing: 1.1)),
        const SizedBox(height: 10),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(color: p.bullSoft, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 14, color: p.bull),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(line, style: AppFonts.sans(size: 14, color: p.ink2, height: 1.45)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UpdateButton extends StatelessWidget {
  final bool opening;
  final VoidCallback onPressed;
  const _UpdateButton({required this.opening, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: opening ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: p.action,
          disabledBackgroundColor: p.action.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: opening
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.system_update_alt_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text('Update now', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: Colors.white)),
                ],
              ),
      ),
    );
  }
}

class _StoreCaption extends StatelessWidget {
  const _StoreCaption();

  @override
  Widget build(BuildContext context) {
    final p = AppColors.p;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_rounded, size: 14, color: p.ink5),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Free on Google Play · your data stays safe',
            textAlign: TextAlign.center,
            style: AppFonts.sans(size: 12, color: p.ink5),
          ),
        ),
      ],
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
