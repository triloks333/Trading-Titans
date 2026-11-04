import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../screens/main/news_list_screen.dart';
import '../screens/main/news_reader_screen.dart';
import '../services/currency_service.dart';
import '../services/supabase_service.dart';

/// News markets as tagged in `blog_posts.excerpt` (`[market:crypto] ...`).
/// Shared with [NewsListScreen], which filters on the same keys.
const Map<String, String> newsMarketLabels = {
  'all': 'Global Markets',
  'stock': 'Indian Stocks',
  'us_stock': 'US Stocks',
  'crypto': 'Crypto',
  'pakistan_stock': 'Pakistan Stocks',
  'italy_stock': 'Italy Stocks',
};

Map<String, Color> newsMarketColors = {
  'all': AppColors.imperialGold,
  'stock': AppColors.bull,
  'us_stock': AppColors.violet,
  'crypto': AppColors.crown,
  'pakistan_stock': AppColors.bull,
  'italy_stock': AppColors.imperialGold,
};

/// Splits the `[market:key]` tag off an excerpt. Untagged posts are global.
({String marketKey, String cleanExcerpt}) parseNewsExcerpt(String? raw) {
  if (raw == null || raw.isEmpty) {
    return (marketKey: 'all', cleanExcerpt: '');
  }
  final match = RegExp(r'^\[market:([a-z_]+)\]\s*(.*)$', dotAll: true).firstMatch(raw);
  if (match != null) {
    return (
      marketKey: match.group(1) ?? 'all',
      cleanExcerpt: match.group(2) ?? '',
    );
  }
  return (marketKey: 'all', cleanExcerpt: raw);
}

/// Animated market news and intelligence section on the Home Dashboard.
///
/// Filters articles according to the user's preferred markets (Indian stocks,
/// US stocks, Crypto, Pakistan stocks, Italy stocks) and allows one-tap
/// reading with an in-app lock card connecting to the official web blog.
class HomeNewsSection extends StatefulWidget {
  const HomeNewsSection({super.key});

  @override
  State<HomeNewsSection> createState() => _HomeNewsSectionState();
}

class _HomeNewsSectionState extends State<HomeNewsSection> with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const int _homeLimit = 12;

  Timer? _autoSlideTimer;
  int _currentPage = 0;
  bool _loading = true;
  List<Map<String, dynamic>> _allPosts = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.90, initialPage: 0);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadNews();
    CurrencyService.instance.addListener(_onPreferencesChanged);
  }

  void _onPreferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CurrencyService.instance.removeListener(_onPreferencesChanged);
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadNews() async {
    try {
      final posts = await SupabaseService().listBlogPosts();
      if (!mounted) return;
      setState(() {
        _allPosts = posts.where((p) => p['published_at'] != null).toList();
        _loading = false;
      });
      _startAutoSlide();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 5500), (_) {
      final filtered = _getFilteredPosts();
      if (!mounted || !_pageController.hasClients || filtered.length <= 1) return;
      final nextPage = (_currentPage + 1) % filtered.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  List<Map<String, dynamic>> _getFilteredPosts() {
    if (_allPosts.isEmpty) return const [];
    final preferred = CurrencyService.instance.preferredMarkets;

    final matched = _allPosts.where((post) {
      final rawExcerpt = post['excerpt'] as String?;
      final parsed = parseNewsExcerpt(rawExcerpt);
      if (parsed.marketKey == 'all') return true;
      return preferred.contains(parsed.marketKey);
    }).toList();

    // If user's preferred filter returned empty, fallback to all published.
    // Capped so the dot row fits on a phone; the rest live behind "View more".
    return (matched.isNotEmpty ? matched : _allPosts).take(_homeLimit).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }

    final filteredPosts = _getFilteredPosts();
    if (filteredPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.bull.withValues(alpha: _pulseAnimation.value),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.bull.withValues(alpha: _pulseAnimation.value * 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Market Intel & News',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NewsListScreen(posts: _allPosts)),
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View more',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.imperialGold,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.imperialGold),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Carousel Container
        SizedBox(
          height: 186,
          child: PageView.builder(
            controller: _pageController,
            itemCount: filteredPosts.length,
            onPageChanged: (idx) {
              setState(() => _currentPage = idx);
            },
            itemBuilder: (context, index) {
              final post = filteredPosts[index];
              return _buildNewsCard(post);
            },
          ),
        ),

        // Dots indicator when multiple posts exist
        if (filteredPosts.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(filteredPosts.length, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: active ? AppColors.imperialGold : AppColors.birch,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildNewsCard(Map<String, dynamic> post) {
    final title = post['title'] as String? ?? 'Market Update';
    final coverUrl = post['cover_url'] as String?;
    final rawExcerpt = post['excerpt'] as String?;
    final publishedAt = post['published_at'] as String?;

    final parsed = parseNewsExcerpt(rawExcerpt);
    final marketKey = parsed.marketKey;
    final cleanExcerpt = parsed.cleanExcerpt;
    final marketLabel = newsMarketLabels[marketKey] ?? 'Market News';
    final tagColor = newsMarketColors[marketKey] ?? AppColors.imperialGold;

    DateTime? publishDate;
    if (publishedAt != null) {
      publishDate = DateTime.tryParse(publishedAt);
    }
    final formattedDate = publishDate != null
        ? DateFormat('d MMM').format(publishDate)
        : 'Today';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NewsReaderScreen(post: post)),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.birch, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left content column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Market pill + date
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                marketLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: tagColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formattedDate,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 10.5,
                              color: AppColors.ink4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Title
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          height: 1.25,
                        ),
                      ),
                      if (cleanExcerpt.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          cleanExcerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11.5,
                            color: AppColors.ink3,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Bottom Action Link
                  Row(
                    children: [
                      Text(
                        'Read preview',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.imperialGold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: AppColors.imperialGold,
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppColors.ink4,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Optional cover image thumbnail on right
            if (coverUrl != null && coverUrl.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  width: 84,
                  height: 112,
                  child: Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.cream,
                      child: Icon(Icons.newspaper, color: AppColors.ink5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
