import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// A luxury, animated hero promotional banner for Trading Titans.
/// Features:
/// - Smooth repeating diagonal specular sheen glint.
/// - Breathing ambient radial glow and micro-floating motion.
/// - Nudging CTA arrow animation.
/// - Spring-scale tactile feedback with haptic response on tap.
/// - Rich multi-stop dark vignette & luxury metallic gradient border.
class AnimatedPremiumBanner extends StatefulWidget {
  final VoidCallback onTap;

  const AnimatedPremiumBanner({
    super.key,
    required this.onTap,
  });

  @override
  State<AnimatedPremiumBanner> createState() => _AnimatedPremiumBannerState();
}

class _AnimatedPremiumBannerState extends State<AnimatedPremiumBanner>
    with TickerProviderStateMixin {
  late final AnimationController _sheenController;
  late final Animation<double> _sheenAnimation;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    // Specular sheen sweep every 3.6 seconds (active sweep for first 38% of cycle)
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _sheenAnimation = CurvedAnimation(
      parent: _sheenController,
      curve: const Interval(0.0, 0.38, curve: Curves.easeInOutCubic),
    );

    // Subtle breathing pulse (glow + micro-float + arrow slide)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _sheenController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            final pulse = _pulseAnimation.value;

            return Container(
              width: double.infinity,
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                // Glowing luxury dual-tone gradient border
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFFD700).withValues(alpha: 0.65),
                    const Color(0xFF00E5FF).withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.12),
                    const Color(0xFFFFB800).withValues(alpha: 0.45),
                  ],
                  stops: const [0.0, 0.35, 0.70, 1.0],
                ),
                boxShadow: [
                  // Ambient neon glow
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.12 + 0.08 * pulse),
                    blurRadius: 24,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                  // Warm gold depth
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.08 + 0.06 * pulse),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                  // Deep drop shadow
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(1.2), // Creates 1.2px metallic border
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl - 1.2),
                child: Stack(
                  children: [
                    // Layer 1: Background 3D Artwork with subtle breathing float
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(0, -2.5 * pulse),
                        child: Transform.scale(
                          scale: 1.03 + 0.015 * pulse,
                          child: Image.asset(
                            'assets/images/topup_banner.jpg',
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),

                    // Layer 2: Deep Cinematic Vignette Gradient for pristine text readability
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              const Color(0xFF060A14),
                              const Color(0xFF060A14).withValues(alpha: 0.94),
                              const Color(0xFF060A14).withValues(alpha: 0.68),
                              const Color(0xFF060A14).withValues(alpha: 0.20),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.42, 0.65, 0.85, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Layer 3: Ambient Radial Glow behind the vault
                    Positioned(
                      right: -20,
                      top: -20,
                      bottom: -20,
                      width: 180,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF00E5FF).withValues(alpha: 0.16 * pulse),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Layer 4: Foreground Content (Badge, Headline, Subtitle, CTA)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Luxury Tag / Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B132B).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: Color.lerp(
                                  const Color(0xFFFFD700).withValues(alpha: 0.4),
                                  const Color(0xFFFFD700).withValues(alpha: 0.85),
                                  pulse,
                                )!,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.18 * pulse),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF22C55E),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF22C55E).withValues(alpha: 0.8),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'START FROM ₹199',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFFD700),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  Icons.bolt_rounded,
                                  size: 13,
                                  color: Color(0xFFFFD700),
                                ),
                              ],
                            ),
                          ),

                          // Text Section
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Boost Your Capital',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.8),
                                      offset: const Offset(0, 2),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 210),
                                child: Text(
                                  'Get instant demo funds to trade F&O and Equity without limits',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFFCBD5E1),
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // CTA Button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Top Up Now',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF090D16),
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Transform.translate(
                                  offset: Offset(pulse * 3.0, 0),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 13,
                                    color: Color(0xFF090D16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Layer 5: Diagonal Metallic Specular Sheen Glint Sweep
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _sheenAnimation,
                          builder: (context, _) {
                            final t = _sheenAnimation.value;
                            if (t <= 0.0 || t >= 1.0) {
                              return const SizedBox.shrink();
                            }

                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final height = constraints.maxHeight;
                                final currentX = -width * 0.4 + t * (width * 1.8);

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(AppRadius.xl - 1.2),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: currentX,
                                        top: -height * 0.6,
                                        bottom: -height * 0.6,
                                        width: 75,
                                        child: Transform.rotate(
                                          angle: 0.36,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.white.withValues(alpha: 0.0),
                                                  Colors.white.withValues(alpha: 0.10),
                                                  Colors.white.withValues(alpha: 0.32),
                                                  Colors.white.withValues(alpha: 0.10),
                                                  Colors.white.withValues(alpha: 0.0),
                                                ],
                                                stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
