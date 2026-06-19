import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Animated shimmer wrapper. Wrap any layout of [SkeletonBox]es in a single
/// [Shimmer] so the highlight sweeps across all of them uniformly. Colors come
/// from [AppColors] so the effect adapts to light/dark themes automatically.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.sand;
    final highlight = AppColors.cream;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlideGradientTransform(_controller.value * 2 - 1),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlideGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

/// A single placeholder block. Defaults to a thin "line" of text.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.sand,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Circular placeholder (avatars / instrument badges).
class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.sand, shape: BoxShape.circle),
    );
  }
}

/// A generic card-row placeholder used by list-style screens (wallet,
/// watchlist, orders, tickets, etc.).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppCard.secondary,
      child: Row(
        children: [
          const SkeletonCircle(size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 120, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 80, height: 11),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              SkeletonBox(width: 60, height: 14),
              SizedBox(height: 8),
              SkeletonBox(width: 40, height: 11),
            ],
          ),
        ],
      ),
    );
  }
}

/// Generic full-screen list skeleton (shimmering card rows).
class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;
  const ListSkeleton({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(itemCount, (_) => const SkeletonCard()),
      ),
    );
  }
}

/// Loading placeholder that mirrors the Dashboard (Home) layout.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting + top action icons
            Row(
              children: [
                const SkeletonCircle(size: 44),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 90, height: 11),
                    SizedBox(height: 8),
                    SkeletonBox(width: 140, height: 16),
                  ],
                ),
                const Spacer(),
                const SkeletonCircle(size: 36),
                const SizedBox(width: 8),
                const SkeletonCircle(size: 36),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Total portfolio value card
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.sand,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 140, height: 11),
                  const SizedBox(height: AppSpacing.sm),
                  const SkeletonBox(width: 200, height: 34),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: const [
                      Expanded(child: SkeletonBox(height: 48)),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: SkeletonBox(height: 48)),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(child: SkeletonBox(height: 48)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Action buttons row
            Row(
              children: const [
                Expanded(child: SkeletonBox(height: 72, radius: 12)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: SkeletonBox(height: 72, radius: 12)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: SkeletonBox(height: 72, radius: 12)),
                SizedBox(width: AppSpacing.md),
                Expanded(child: SkeletonBox(height: 72, radius: 12)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Market pulse header + cards
            const SkeletonBox(width: 130, height: 18),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 90,
              child: Row(
                children: const [
                  Expanded(child: SkeletonBox(height: 90, radius: 12)),
                  SizedBox(width: AppSpacing.md),
                  Expanded(child: SkeletonBox(height: 90, radius: 12)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Holdings header + rows
            const SkeletonBox(width: 110, height: 16),
            const SizedBox(height: AppSpacing.sm),
            const SkeletonCard(),
            const SkeletonCard(),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder that mirrors the Portfolio layout (summary card + tabs +
/// position cards).
class PortfolioSkeleton extends StatelessWidget {
  const PortfolioSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 140, height: 26),
                  SizedBox(height: 8),
                  SkeletonBox(width: 180, height: 12),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Summary card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.sand,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 120, height: 10),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 160, height: 30),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: const [
                      Expanded(child: SkeletonBox(height: 36)),
                      SizedBox(width: AppSpacing.md),
                      Expanded(child: SkeletonBox(height: 36)),
                      SizedBox(width: AppSpacing.md),
                      Expanded(child: SkeletonBox(height: 36)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Tab bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: const [
                  SkeletonBox(width: 90, height: 14),
                  SizedBox(width: AppSpacing.lg),
                  SkeletonBox(width: 110, height: 14),
                  SizedBox(width: AppSpacing.lg),
                  SkeletonBox(width: 70, height: 14),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Position cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: const [
                  SkeletonCard(),
                  SkeletonCard(),
                  SkeletonCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
