import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../services/theme_service.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/home_news_section.dart';
import 'news_reader_screen.dart';

/// Short chip labels for the market a post is tagged with, in display order.
const Map<String, String> kNewsChipLabels = {
  'stock': 'India', 'us_stock': 'US', 'crypto': 'Crypto', 'pakistan_stock': 'Pakistan', 'italy_stock': 'Italy',
  'all': 'Global',
};

/// "1H AGO", "YESTERDAY", "3D AGO", or a date once it is over a week old.
String newsAge(String? publishedAt, {DateTime? now}) {
  final dt = DateTime.tryParse(publishedAt ?? '');
  if (dt == null) return '';
  final d = (now ?? DateTime.now()).toUtc().difference(dt.toUtc());
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}M AGO';
  if (d.inHours < 24) return '${d.inHours}H AGO';
  if (d.inDays == 1) return 'YESTERDAY';
  if (d.inDays < 7) return '${d.inDays}D AGO';
  return DateFormat('d MMM').format(dt.toLocal()).toUpperCase();
}

/// Reading time at ~200 words a minute, at least one minute.
int newsReadMinutes(String? markdown) {
  final words = RegExp(r'\S+').allMatches(markdown ?? '').length;
  return (words / 200).ceil().clamp(1, 60);
}

/// Every news post, behind the home carousel's "View more". Takes the posts the
/// carousel already loaded rather than fetching again, and shows all markets.
class NewsListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> posts;

  const NewsListScreen({super.key, required this.posts});

  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  String? _market; // null = All
  DateTimeRange? _range;

  String _marketOf(Map<String, dynamic> p) => parseNewsExcerpt(p['excerpt'] as String?).marketKey;

  DateTime? _dateOf(Map<String, dynamic> p) => DateTime.tryParse(p['published_at'] as String? ?? '')?.toLocal();

  List<Map<String, dynamic>> get _visible => widget.posts.where((p) {
        if (_market != null && _marketOf(p) != _market) return false;
        if (_range != null) {
          final d = _dateOf(p);
          if (d == null) return false;
          final day = DateTime(d.year, d.month, d.day);
          if (day.isBefore(_range!.start) || day.isAfter(_range!.end)) return false;
        }
        return true;
      }).toList();

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _open(Map<String, dynamic> post) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsReaderScreen(post: post)));

  @override
  Widget build(BuildContext context) {
    final present = widget.posts.map(_marketOf).toSet();
    final markets = kNewsChipLabels.keys.where(present.contains).toList();
    final posts = _visible;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Market news', style: AppFonts.sans(size: 20, weight: FontWeight.w700, color: AppColors.ink)),
              ),
              Badge(
                isLabelVisible: _range != null,
                smallSize: 8,
                backgroundColor: AppColors.goldMid,
                child: AuthIconButton(icon: Icons.date_range_outlined, label: 'Filter by date', onTap: _pickDates),
              ),
              const SizedBox(width: 10),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
            child: Row(children: [
              _chip('All', null),
              for (final m in markets) _chip(kNewsChipLabels[m]!, m),
            ]),
          ),
          if (_range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 10),
              child: Row(children: [
                Icon(Icons.event_outlined, size: 14, color: AppColors.ink4),
                const SizedBox(width: 6),
                Text(
                    '${DateFormat('d MMM').format(_range!.start)} – ${DateFormat('d MMM yyyy').format(_range!.end)}',
                    style: AppFonts.sans(size: 12, color: AppColors.ink3)),
                const Spacer(),
                TextButton(onPressed: () => setState(() => _range = null), child: const Text('Clear dates')),
              ]),
            ),
          Divider(color: AppColors.birch),
          Expanded(
            child: posts.isEmpty
                ? Center(
                    child: Text(
                      widget.posts.isEmpty ? 'No news yet.' : 'No news for this filter.',
                      style: AppFonts.sans(size: 14, color: AppColors.ink3),
                    ),
                  )
                : ListView.builder(
                    itemCount: posts.length,
                    itemBuilder: (_, i) => i == 0 ? _lead(posts[0]) : _row(posts[i]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, String? market) {
    final on = _market == market;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        labelStyle: AppFonts.sans(size: 13, weight: FontWeight.w500, color: on ? AppColors.goldMid : AppColors.ink3),
        side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch),
        onSelected: (_) => setState(() => _market = market),
      ),
    );
  }

  Widget _tag(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(color?.withValues(alpha: 0.14) ?? AppColors.cream),
        child: Text(text, style: AppText.badge.copyWith(color: color ?? AppColors.ink3)),
      );

  /// Newest post as the lead story: full-width cover, tags, serif headline, summary.
  Widget _lead(Map<String, dynamic> post) {
    final parsed = parseNewsExcerpt(post['excerpt'] as String?);
    final cover = post['cover_url'] as String?;
    return InkWell(
      onTap: () => _open(post),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          NewsCover(url: cover, market: parsed.marketKey, height: 170),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _tag((kNewsChipLabels[parsed.marketKey] ?? 'Global').toUpperCase(), color: newsMarketColors[parsed.marketKey]),
            if (newsAge(post['published_at'] as String?).isNotEmpty) _tag(newsAge(post['published_at'] as String?)),
            _tag('${newsReadMinutes(post['body_markdown'] as String?)} MIN READ'),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(post['title'] as String? ?? 'Market update',
              style: GoogleSerif.headline(20)),
          if (parsed.cleanExcerpt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(parsed.cleanExcerpt,
                maxLines: 3, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 13, color: AppColors.ink3, height: 1.4)),
          ],
        ]),
      ),
    );
  }

  /// Every other post: age tag, headline, 76 x 64 thumbnail on the right.
  Widget _row(Map<String, dynamic> post) {
    final parsed = parseNewsExcerpt(post['excerpt'] as String?);
    final age = newsAge(post['published_at'] as String?);
    return InkWell(
      onTap: () => _open(post),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                _tag((kNewsChipLabels[parsed.marketKey] ?? 'Global').toUpperCase(), color: newsMarketColors[parsed.marketKey]),
                if (age.isNotEmpty) _tag(age),
              ]),
              const SizedBox(height: 6),
              Text(post['title'] as String? ?? 'Market update',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink, height: 1.35)),
            ]),
          ),
          const SizedBox(width: AppSpacing.md),
          NewsCover(url: post['cover_url'] as String?, market: parsed.marketKey, width: 76, height: 64),
        ]),
      ),
    );
  }
}

/// IBM Plex Serif for long-read headlines and body, as in the design.
class GoogleSerif {
  static TextStyle headline(double size) =>
      AppFonts.serif(size: size, weight: FontWeight.w600, color: AppColors.ink, height: 1.28);
}

/// A post's cover image, or a market-tinted placeholder when there is none or
/// it fails to load, so every row keeps its shape.
class NewsCover extends StatelessWidget {
  const NewsCover({super.key, required this.url, required this.market, this.width, required this.height});
  final String? url;
  final String market;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tint = newsMarketColors[market] ?? AppColors.goldMid;
    final placeholder = Container(
      width: width ?? double.infinity,
      height: height,
      color: tint.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(Icons.article_outlined, color: tint, size: height > 100 ? 36 : 22),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: url == null || url!.isEmpty
          ? placeholder
          : AppNetworkImage(url: url!, width: width ?? double.infinity, height: height),
    );
  }
}
