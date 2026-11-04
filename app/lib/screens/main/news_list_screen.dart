import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../widgets/home_news_section.dart';
import 'news_reader_screen.dart';

/// Every news post, behind the home carousel's "View more".
///
/// Takes the posts the carousel already loaded rather than fetching again. Shows
/// all markets, not just the user's preferred ones, because this is where people
/// come to look past their own feed. Filtered by a date range and by market,
/// which is how posts are tagged ("countries" in practice: India, US, Pakistan,
/// Italy, plus Crypto and Global).
class NewsListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> posts;

  const NewsListScreen({super.key, required this.posts});

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  DateTimeRange? _range;
  final Set<String> _markets = {};

  DateTime? _dateOf(Map<String, dynamic> post) =>
      DateTime.tryParse(post['published_at'] as String? ?? '')?.toLocal();

  List<Map<String, dynamic>> get _visible => widget.posts.where((post) {
        final date = _dateOf(post);
        if (_range != null) {
          if (date == null) return false;
          final day = DateTime(date.year, date.month, date.day);
          if (day.isBefore(_range!.start) || day.isAfter(_range!.end)) return false;
        }
        if (_markets.isNotEmpty &&
            !_markets.contains(parseNewsExcerpt(post['excerpt'] as String?).marketKey)) {
          return false;
        }
        return true;
      }).toList();

  bool get _filtered => _range != null || _markets.isNotEmpty;

  Future<void> _openFilters() async {
    var range = _range;
    final markets = {..._markets};

    final apply = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter news',
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: AppSpacing.md),
                Text('Dates',
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(range == null
                      ? 'Any date'
                      : '${DateFormat('d MMM yyyy').format(range!.start)} – '
                          '${DateFormat('d MMM yyyy').format(range!.end)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: sheet,
                      firstDate: DateTime(2025),
                      lastDate: now,
                      initialDateRange: range,
                    );
                    if (picked != null) setSheet(() => range = picked);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Markets',
                    style: GoogleFonts.ibmPlexSans(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in newsMarketLabels.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: markets.contains(e.key),
                        selectedColor: newsMarketColors[e.key]!.withValues(alpha: 0.18),
                        checkmarkColor: newsMarketColors[e.key],
                        onSelected: (on) =>
                            setSheet(() => on ? markets.add(e.key) : markets.remove(e.key)),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setSheet(() {
                        range = null;
                        markets.clear();
                      }),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.imperialGold),
                      onPressed: () => Navigator.pop(sheet, true),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (apply == true) {
      setState(() {
        _range = range;
        _markets
          ..clear()
          ..addAll(markets);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _visible;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        elevation: 0,
        title: Text('Market Intel & News',
            style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w800, color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _filtered,
              backgroundColor: AppColors.imperialGold,
              smallSize: 8,
              child: Icon(Icons.tune_rounded, color: AppColors.ink),
            ),
          ),
        ],
      ),
      body: posts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_filtered ? 'No news matches these filters.' : 'No news yet.',
                        style: GoogleFonts.ibmPlexSans(fontSize: 14, color: AppColors.ink3)),
                    if (_filtered)
                      TextButton(
                        onPressed: () => setState(() {
                          _range = null;
                          _markets.clear();
                        }),
                        child: const Text('Clear filters'),
                      ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: posts.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) => _tile(posts[i]),
            ),
    );
  }

  Widget _tile(Map<String, dynamic> post) {
    final parsed = parseNewsExcerpt(post['excerpt'] as String?);
    final colour = newsMarketColors[parsed.marketKey] ?? AppColors.imperialGold;
    final date = _dateOf(post);
    final cover = post['cover_url'] as String?;

    return Material(
      color: AppColors.pureWhite,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NewsReaderScreen(post: post)),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.birch),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: colour.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              newsMarketLabels[parsed.marketKey] ?? 'Market News',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.ibmPlexSans(
                                  fontSize: 10, fontWeight: FontWeight.w700, color: colour),
                            ),
                          ),
                        ),
                        if (date != null) ...[
                          const SizedBox(width: 8),
                          Text(DateFormat('d MMM yyyy').format(date),
                              style: GoogleFonts.ibmPlexSans(fontSize: 10.5, color: AppColors.ink4)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      post['title'] as String? ?? 'Market Update',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.ibmPlexSans(
                          fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.25),
                    ),
                    if (parsed.cleanExcerpt.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        parsed.cleanExcerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink3, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              if (cover != null && cover.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(
                    cover,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
