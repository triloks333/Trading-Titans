import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../services/plan_service.dart';
import '../screens/main/subscribe_screen.dart';
import '../screens/main/glossary_screen.dart';
import 'animated_premium_banner.dart';
import 'report_issue_sheet.dart';
import 'request_feature_sheet.dart';

/// A 3-slide auto-sliding carousel on the home dashboard.
/// Automatically slides every 4.5 seconds, with manual swipe support and page dots.
///
/// Slides:
/// 1. Quick Capital Boost (Top-up starting ₹199) -> SubscribeScreen
/// 2. Titan Pro ₹999 Pack (Twice-weekly live founder mentorship + ₹1L+/mo value) -> SubscribeScreen
/// 3. Trading Glossary & Quiz (Options, Greeks, plain English) -> GlossaryScreen
/// 4. Request a feature / Report an issue -> the same sheets as Settings
class HomeBannerCarousel extends StatefulWidget {
  final VoidCallback? onSubscribeTap;
  final VoidCallback? onGlossaryTap;
  final Duration autoSlideDuration;

  const HomeBannerCarousel({
    super.key,
    this.onSubscribeTap,
    this.onGlossaryTap,
    this.autoSlideDuration = const Duration(milliseconds: 4500),
  });

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoSlideTimer;
  static const int _bannerCount = 4;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startAutoSlideTimer();
  }

  void _startAutoSlideTimer() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(widget.autoSlideDuration, (timer) {
      if (!mounted || !_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % _bannerCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _resetTimer() {
    _startAutoSlideTimer();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToTopUp() {
    if (widget.onSubscribeTap != null) {
      widget.onSubscribeTap!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscribeScreen(initialTabIndex: 1)),
      );
    }
  }

  void _navigateToMentorship() {
    if (widget.onSubscribeTap != null) {
      widget.onSubscribeTap!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscribeScreen(initialTabIndex: 0)),
      );
    }
  }

  void _navigateToGlossary() {
    if (widget.onGlossaryTap != null) {
      widget.onGlossaryTap!();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const GlossaryScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 170,
          child: PageView(
            controller: _pageController,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
              _resetTimer();
            },
            children: [
              // Slide 1: Capital Boost Top-Up
              AnimatedPremiumBanner(
                onTap: _navigateToTopUp,
              ),

              // Slide 2: Titan Pro ₹999 Pack with Dedicated Mentorship
              _MentorshipBanner(
                onTap: _navigateToMentorship,
              ),

              // Slide 3: Trading Glossary & Educational Hub
              _GlossaryBanner(
                onTap: _navigateToGlossary,
              ),

              // Slide 4: Feedback, moved up from the bottom of Settings
              const _FeedbackBanner(),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Carousel Indicator Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_bannerCount, (i) {
            final isActive = _currentPage == i;
            return GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 22 : 6,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  color: isActive
                      ? AppColors.crown
                      : Colors.white.withValues(alpha: 0.22),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.crown.withValues(alpha: 0.45),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Slide 2: Luxury Titan Pro ₹999 Pack Banner
/// Highlighting twice-weekly live founder mentorship, ₹1L+/month value anchor, and ₹10L demo capital.
class _MentorshipBanner extends StatefulWidget {
  final VoidCallback onTap;

  const _MentorshipBanner({required this.onTap});

  @override
  State<_MentorshipBanner> createState() => _MentorshipBannerState();
}

class _MentorshipBannerState extends State<_MentorshipBanner>
    with TickerProviderStateMixin {
  late final AnimationController _sheenController;
  late final Animation<double> _sheenAnimation;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _sheenAnimation = CurvedAnimation(
      parent: _sheenController,
      curve: const Interval(0.0, 0.38, curve: Curves.easeInOutCubic),
    );

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
      behavior: HitTestBehavior.opaque,
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
                // Glowing luxury dual-tone gradient border (Amethyst + Gold)
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.crown.withValues(alpha: 0.70),
                    const Color(0xFFC084FC).withValues(alpha: 0.50),
                    Colors.white.withValues(alpha: 0.15),
                    const Color(0xFFEAB308).withValues(alpha: 0.60),
                  ],
                  stops: const [0.0, 0.40, 0.75, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFC084FC).withValues(alpha: 0.14 + 0.08 * pulse),
                    blurRadius: 24,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: AppColors.crown.withValues(alpha: 0.10 + 0.07 * pulse),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.50),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(1.2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl - 1.2),
                child: Stack(
                  children: [
                    // Layer 1: 3D Artwork Background with ambient breathing motion
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(0, -2.5 * pulse),
                        child: Transform.scale(
                          scale: 1.03 + 0.015 * pulse,
                          child: Image.asset(
                            'assets/images/mentorship_banner.jpg',
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
                              const Color(0xFF090714),
                              const Color(0xFF090714).withValues(alpha: 0.95),
                              const Color(0xFF090714).withValues(alpha: 0.72),
                              const Color(0xFF090714).withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.44, 0.68, 0.86, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Layer 3: Ambient Radial Glow behind the artwork
                    Positioned(
                      right: -25,
                      top: -20,
                      bottom: -20,
                      width: 190,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFFC084FC).withValues(alpha: 0.20 * pulse),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Layer 4: Foreground Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Luxury Tag / Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1338).withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: Color.lerp(
                                  AppColors.crown.withValues(alpha: 0.45),
                                  AppColors.crown.withValues(alpha: 0.90),
                                  pulse,
                                )!,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.crown.withValues(alpha: 0.20 * pulse),
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
                                    color: AppColors.crown,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.crown.withValues(alpha: 0.85),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'FOUNDER MENTORSHIP · ₹1L+/MO VALUE',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.crown,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(width: 3.5),
                                const Icon(
                                  Icons.workspace_premium_rounded,
                                  size: 13,
                                  color: AppColors.crown,
                                ),
                              ],
                            ),
                          ),

                          // Text Section
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Titan Pro Membership',
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 18.5,
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
                              const SizedBox(height: 2.5),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 225),
                                child: Text(
                                  'Twice-weekly live 1-on-1 mentorship with founders, ₹10L demo capital & F&O unlocked',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.ibmPlexSans(
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFDF70), Color(0xFFE6A100)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.crown.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.40),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Join for ${PlanService.instance.marketingRupees(999)}',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1B1100),
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Transform.translate(
                                  offset: Offset(pulse * 3.0, 0),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 13,
                                    color: Color(0xFF1B1100),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Layer 5: Diagonal Specular Sheen Sweep
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _sheenAnimation,
                          builder: (context, _) {
                            final t = _sheenAnimation.value;
                            if (t <= 0.0 || t >= 1.0) return const SizedBox.shrink();

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

/// Slide 3: Luxury Trading Glossary & Quiz Hub Banner
/// Highlighting Options, Greeks, and the knowledge quiz with zero risk.
class _GlossaryBanner extends StatefulWidget {
  final VoidCallback onTap;

  const _GlossaryBanner({required this.onTap});

  @override
  State<_GlossaryBanner> createState() => _GlossaryBannerState();
}

class _GlossaryBannerState extends State<_GlossaryBanner>
    with TickerProviderStateMixin {
  late final AnimationController _sheenController;
  late final Animation<double> _sheenAnimation;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _sheenAnimation = CurvedAnimation(
      parent: _sheenController,
      curve: const Interval(0.0, 0.38, curve: Curves.easeInOutCubic),
    );

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
      behavior: HitTestBehavior.opaque,
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
                // Glowing luxury dual-tone gradient border (Mint + Cyan)
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF00F5A0).withValues(alpha: 0.70),
                    const Color(0xFF00D2FF).withValues(alpha: 0.50),
                    Colors.white.withValues(alpha: 0.15),
                    const Color(0xFF10B981).withValues(alpha: 0.60),
                  ],
                  stops: const [0.0, 0.40, 0.75, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F5A0).withValues(alpha: 0.14 + 0.08 * pulse),
                    blurRadius: 24,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: const Color(0xFF00D2FF).withValues(alpha: 0.10 + 0.07 * pulse),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.50),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(1.2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl - 1.2),
                child: Stack(
                  children: [
                    // Layer 1: 3D Artwork Background with ambient breathing motion
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(0, -2.5 * pulse),
                        child: Transform.scale(
                          scale: 1.03 + 0.015 * pulse,
                          child: Image.asset(
                            'assets/images/glossary_banner.jpg',
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
                              const Color(0xFF04120D),
                              const Color(0xFF04120D).withValues(alpha: 0.95),
                              const Color(0xFF04120D).withValues(alpha: 0.72),
                              const Color(0xFF04120D).withValues(alpha: 0.22),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.44, 0.68, 0.86, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Layer 3: Ambient Radial Glow behind the artwork
                    Positioned(
                      right: -25,
                      top: -20,
                      bottom: -20,
                      width: 190,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF00F5A0).withValues(alpha: 0.20 * pulse),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Layer 4: Foreground Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Luxury Tag / Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF07241A).withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: Color.lerp(
                                  const Color(0xFF00F5A0).withValues(alpha: 0.45),
                                  const Color(0xFF00F5A0).withValues(alpha: 0.90),
                                  pulse,
                                )!,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00F5A0).withValues(alpha: 0.20 * pulse),
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
                                    color: const Color(0xFF00F5A0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00F5A0).withValues(alpha: 0.85),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'KNOWLEDGE HUB · ZERO RISK',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF00F5A0),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(width: 3.5),
                                const Icon(
                                  Icons.auto_stories_rounded,
                                  size: 13,
                                  color: Color(0xFF00F5A0),
                                ),
                              ],
                            ),
                          ),

                          // Text Section
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Master Trading Terms',
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 18.5,
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
                              const SizedBox(height: 2.5),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 225),
                                child: Text(
                                  'Options, Greeks & Market Mechanics decoded in plain English with interactive quiz',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.ibmPlexSans(
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00F5A0), Color(0xFF00C980)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00F5A0).withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.40),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Explore Glossary',
                                  style: GoogleFonts.ibmPlexSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF021B13),
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Transform.translate(
                                  offset: Offset(pulse * 3.0, 0),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 13,
                                    color: Color(0xFF021B13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Layer 5: Diagonal Specular Sheen Sweep
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _sheenAnimation,
                          builder: (context, _) {
                            final t = _sheenAnimation.value;
                            if (t <= 0.0 || t >= 1.0) return const SizedBox.shrink();

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

/// Slide 4: the two feedback sheets, one tap from home.
///
/// They used to live only at the bottom of Settings, where almost nobody found
/// them. Opens the exact sheets the profile menu does, so there is one form each.
class _FeedbackBanner extends StatefulWidget {
  const _FeedbackBanner();

  @override
  State<_FeedbackBanner> createState() => _FeedbackBannerState();
}

class _FeedbackBannerState extends State<_FeedbackBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        final t = Curves.easeInOutSine.transform(_glow.value);
        return Container(
          height: 170,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0F1B33),
                Color.lerp(const Color(0xFF1E3A8A), const Color(0xFF0E7490), t)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.12 + 0.18 * t),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum_rounded, color: Color(0xFF7DD3FC), size: 18),
              const SizedBox(width: 6),
              Text(
                'HELP US BUILD TRADING TITANS',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: const Color(0xFF7DD3FC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Have an idea or spotted a bug?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'We read every one. Good ideas can earn a reward.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSans(fontSize: 12, color: Colors.white70),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _action(
                  Icons.rocket_launch_rounded,
                  'Request a feature',
                  () => showRequestFeatureSheet(context),
                  filled: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _action(
                  Icons.bug_report_rounded,
                  'Report an issue',
                  () => showReportIssueSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool filled = false}) {
    return Material(
      color: filled ? AppColors.crown : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: Colors.white24),
                ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: filled ? const Color(0xFF0F1B33) : Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: filled ? const Color(0xFF0F1B33) : Colors.white,
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
