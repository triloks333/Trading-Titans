import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';

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
    final inkColor = isDark ? const Color(0xFFF9F9FB) : const Color(0xFF0F172A);
    const goldColor = Color(0xFFF1C40F);

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
                child: const Icon(
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
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              const SizedBox(
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

  const HardUpdateGate({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: HardUpdateScreen(
        updateUrl: updateUrl,
        releaseNotes: releaseNotes,
      ),
    );
  }
}

class HardUpdateScreen extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;

  const HardUpdateScreen({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
  });

  @override
  State<HardUpdateScreen> createState() => _HardUpdateScreenState();
}

class _HardUpdateScreenState extends State<HardUpdateScreen> {
  /// Attempts to open the store. On failure (unparseable url, launchUrl
  /// returning false, or a thrown error) the gate is kept and an error is
  /// shown; the gate is never dismissed by this control (R8.5, R8.6).
  Future<void> _launchUpdate(BuildContext context) async {
    var launched = false;
    final uri = Uri.tryParse(widget.updateUrl);
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }

    if (!launched && context.mounted) {
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
    final inkColor = isDark ? const Color(0xFFF9F9FB) : const Color(0xFF0F172A);
    final releaseNotes = widget.releaseNotes;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.bull.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    size: 64,
                    color: AppColors.bull,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Update Required',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: inkColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'A new update is available, please update your app',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                if (releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'What\'s New:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: inkColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: releaseNotes
                          .split('\n')
                          .where((line) => line.trim().isNotEmpty)
                          .map((line) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '• ',
                                      style: TextStyle(
                                        color: AppColors.bull,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        line.replaceAll('•', '').trim(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.4,
                                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _launchUpdate(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bull,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Update Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

class SoftUpdateDialog extends StatefulWidget {
  final String updateUrl;
  final String releaseNotes;
  final VoidCallback onDismiss;

  const SoftUpdateDialog({
    super.key,
    required this.updateUrl,
    required this.releaseNotes,
    required this.onDismiss,
  });

  @override
  State<SoftUpdateDialog> createState() => _SoftUpdateDialogState();
}

class _SoftUpdateDialogState extends State<SoftUpdateDialog> {
  /// Attempts to open the store. Returns `true` only when the launch
  /// succeeds; an unparseable url, `launchUrl` returning false, or a thrown
  /// error all yield `false` so the caller can keep the prompt open (R9.4).
  Future<bool> _launchUpdate() async {
    final uri = Uri.tryParse(widget.updateUrl);
    if (uri == null) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Handles the "Update" button: on success closes the (non-blocking) dialog,
  /// on failure keeps it open and surfaces an error (R9.4).
  Future<void> _onUpdatePressed() async {
    final launched = await _launchUpdate();
    if (!mounted) return;
    if (launched) {
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
    final inkColor = isDark ? const Color(0xFFF9F9FB) : const Color(0xFF0F172A);
    final releaseNotes = widget.releaseNotes;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.bull,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Update Available!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: inkColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'A new update is available on the Play Store with performance improvements and new features.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            if (releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'What\'s New:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: inkColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: releaseNotes
                        .split('\n')
                        .where((line) => line.trim().isNotEmpty)
                        .map((line) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '• ',
                                    style: TextStyle(
                                      color: AppColors.bull,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      line.replaceAll('•', '').trim(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.3,
                                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    widget.onDismiss();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Remind Later',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _onUpdatePressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bull,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
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
    final inkColor = isDark ? const Color(0xFFF9F9FB) : const Color(0xFF0F172A);
    final bodyColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded,
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
