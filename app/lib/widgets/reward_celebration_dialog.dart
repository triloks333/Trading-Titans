import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

class RewardCelebrationDialog extends StatefulWidget {
  final double amount;
  final String message;
  final VoidCallback onClose;

  const RewardCelebrationDialog({
    super.key,
    required this.amount,
    required this.message,
    required this.onClose,
  });

  @override
  State<RewardCelebrationDialog> createState() => _RewardCelebrationDialogState();
}

class _RewardCelebrationDialogState extends State<RewardCelebrationDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<ConfettiParticle> _particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        setState(() {
          for (final p in _particles) {
            p.update();
          }
        });
      });

    // Create confetti particles
    final random = Random();
    for (int i = 0; i < 80; i++) {
      _particles.add(ConfettiParticle(
        x: 150.0 + random.nextDouble() * 50,
        y: 150.0 + random.nextDouble() * 50,
        color: [
          Colors.amber,
          Colors.orange,
          Colors.red,
          Colors.blue,
          Colors.green,
          Colors.pink,
          Colors.purple,
          AppColors.imperialGold,
        ][random.nextInt(8)],
        angle: random.nextDouble() * 2 * pi,
        speed: 2.0 + random.nextDouble() * 6.0,
        size: 4.0 + random.nextDouble() * 6.0,
      ));
    }

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Confetti Animation Canvas
          Positioned.fill(
            child: CustomPaint(
              painter: ConfettiPainter(particles: _particles),
            ),
          ),
          // Dialog Content Card
          Container(
            width: 320,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.imperialGold, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.imperialGold.withAlpha(51),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.sm),
                // Celebration Icon / Emote
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: const BoxDecoration(
                    color: AppColors.goldPale,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    size: 48,
                    color: AppColors.imperialGold,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Congratulations! 🎉',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Bug Bounty Reward Claimed',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink4,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+ ₹${widget.amount.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.bull,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Demo Cash',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.ink2,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onClose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    child: Text(
                      'Awesome, Thanks!',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: AppColors.pureWhite,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConfettiParticle {
  double x;
  double y;
  final Color color;
  final double angle;
  final double speed;
  final double size;
  double rotation = 0;
  final double rotationSpeed;

  ConfettiParticle({
    required this.x,
    required this.y,
    required this.color,
    required this.angle,
    required this.speed,
    required this.size,
  }) : rotationSpeed = (Random().nextDouble() - 0.5) * 0.2;

  void update() {
    x += cos(angle) * speed;
    y += sin(angle) * speed + 1.2; // slight gravity pull
    rotation += rotationSpeed;
  }
}

class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;

  ConfettiPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      if (p.x < -50 || p.x > size.width + 50 || p.y < -50 || p.y > size.height + 50) {
        continue;
      }
      paint.color = p.color;
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) => true;
}
