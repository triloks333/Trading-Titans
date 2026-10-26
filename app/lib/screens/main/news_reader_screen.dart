import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_constants.dart';
import '../../core/theme.dart';

/// Renders a published market news/blog post with half-article preview and
/// an interactive lock card redirecting readers to TheTradingTitans.com.
class NewsReaderScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const NewsReaderScreen({
    super.key,
    required this.post,
  });

  @override
  State<NewsReaderScreen> createState() => _NewsReaderScreenState();
}

class _NewsReaderScreenState extends State<NewsReaderScreen> {
  bool _expanded = false;

  Map<String, dynamic> get post => widget.post;

  static const Map<String, String> _marketLabels = {
    'all': 'Global Markets',
    'stock': 'Indian Stocks',
    'us_stock': 'US Stocks',
    'crypto': 'Crypto',
    'pakistan_stock': 'Pakistan Stocks',
    'italy_stock': 'Italy Stocks',
  };

  static const Map<String, Color> _marketColors = {
    'all': Color(0xFF3B82F6),
    'stock': Color(0xFF10B981),
    'us_stock': Color(0xFF6366F1),
    'crypto': Color(0xFFF59E0B),
    'pakistan_stock': Color(0xFF059669),
    'italy_stock': Color(0xFF0284C7),
  };

  ({String marketKey, String cleanExcerpt}) _parseExcerpt(String? raw) {
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

  Future<void> _openFullArticle(BuildContext context, String slug) async {
    final cleanSlug = slug.trim();
    final url = cleanSlug.isNotEmpty
        ? '${AppConstants.marketingSiteUrl}/blog/$cleanSlug'
        : '${AppConstants.marketingSiteUrl}/blog';
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link copied to clipboard:\n$url'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link copied to clipboard:\n$url'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = post['title'] as String? ?? 'Market News';
    final slug = post['slug'] as String? ?? '';
    final coverUrl = post['cover_url'] as String?;
    final rawExcerpt = post['excerpt'] as String?;
    final bodyMarkdown = post['body_markdown'] as String? ?? '';
    final publishedAt = post['published_at'] as String?;

    final parsed = _parseExcerpt(rawExcerpt);
    final marketKey = parsed.marketKey;
    final cleanExcerpt = parsed.cleanExcerpt;
    final marketLabel = _marketLabels[marketKey] ?? 'Market News';
    final tagColor = _marketColors[marketKey] ?? AppColors.imperialGold;

    DateTime? publishDate;
    if (publishedAt != null) {
      publishDate = DateTime.tryParse(publishedAt);
    }
    final formattedDate = publishDate != null
        ? DateFormat('d MMM yyyy').format(publishDate)
        : 'Recent Update';

    // Slice content: full if expanded, else first half
    final rawParagraphs = bodyMarkdown
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    List<String> visibleParagraphs;
    if (_expanded) {
      visibleParagraphs = rawParagraphs;
    } else if (rawParagraphs.length > 1) {
      final halfCount = (rawParagraphs.length / 2).ceil();
      visibleParagraphs = rawParagraphs.take(halfCount.clamp(1, rawParagraphs.length)).toList();
    } else if (bodyMarkdown.isNotEmpty) {
      final cutoff = (bodyMarkdown.length / 2).round();
      final lastSpace = bodyMarkdown.lastIndexOf(' ', cutoff);
      visibleParagraphs = [bodyMarkdown.substring(0, lastSpace > 0 ? lastSpace : cutoff)];
    } else {
      visibleParagraphs = [];
    }

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.parchment,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.open_in_new_outlined, color: AppColors.ink2),
            tooltip: 'Open in Browser',
            onPressed: () => _openFullArticle(context, slug),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image Hero
            if (coverUrl != null && coverUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.cream,
                        child: Center(
                          child: Icon(Icons.broken_image_outlined, color: AppColors.ink5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Market tag and date
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: tagColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  marketLabel,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: tagColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formattedDate,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.ink4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Title
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.3,
                    ),
                  ),

                  // Excerpt / Subtitle
                  if (cleanExcerpt.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      cleanExcerpt,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink3,
                        height: 1.5,
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.md),
                  Divider(color: AppColors.birch),
                  const SizedBox(height: AppSpacing.md),

                  // Article content
                  for (final paragraph in visibleParagraphs)
                    _renderParagraph(paragraph),

                  const SizedBox(height: AppSpacing.md),

                  // Lock card or Expanded Footer
                  if (!_expanded)
                    _buildLockCard(context, slug)
                  else
                    _buildExpandedFooter(context, slug),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderParagraph(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(
          trimmed.substring(4),
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      );
    } else if (trimmed.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          trimmed.substring(3),
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      );
    } else if (trimmed.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          trimmed.substring(2),
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      );
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
              child: Icon(Icons.circle, size: 6, color: AppColors.imperialGold),
            ),
            Expanded(
              child: Text(
                trimmed.substring(2),
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  height: 1.6,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Standard paragraph with bold parsing
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: _renderRichText(trimmed),
    );
  }

  Widget _renderRichText(String text) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: GoogleFonts.inter(
            fontSize: 14.5,
            height: 1.6,
            color: AppColors.ink,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: GoogleFonts.inter(
          fontSize: 14.5,
          height: 1.6,
          fontWeight: FontWeight.bold,
          color: AppColors.ink,
        ),
      ));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: GoogleFonts.inter(
          fontSize: 14.5,
          height: 1.6,
          color: AppColors.ink,
        ),
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildLockCard(BuildContext context, String slug) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.warmWhite.withValues(alpha: 0.6),
            AppColors.warmWhite,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Gradient fade indicator showing reading cutoff
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.imperialGold,
                  Color(0xFFF59E0B),
                  AppColors.bull,
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            child: Column(
              children: [
                // Lock Icon with glowing container
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.imperialGold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.imperialGold.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock_rounded,
                      size: 28,
                      color: AppColors.imperialGold,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                Text(
                  'Continue Reading Full Analysis',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'You have completed the initial breakdown. Unlock the full research note, live chart levels, and deep market thesis on our website.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.ink3,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openFullArticle(context, slug),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.imperialGold,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Read Full Article on Website',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.open_in_new_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _expanded = true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: BorderSide(color: AppColors.birch, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chrome_reader_mode_outlined, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Read Complete Story In-App',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_outlined, size: 13, color: AppColors.ink4),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'thetradingtitans.com  ·  Free Educational Research',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppColors.ink4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedFooter(BuildContext context, String slug) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.bull, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Full Research Note Completed',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Explore more macroeconomic intelligence and daily institutional breakdowns on our official website blog.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.ink3,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openFullArticle(context, slug),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text(
                    'Open on Website',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.imperialGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => setState(() => _expanded = false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink3,
                  side: BorderSide(color: AppColors.birch),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text('Collapse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
