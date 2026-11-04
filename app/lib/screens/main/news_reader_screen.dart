import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_constants.dart';
import '../../core/theme.dart';
import '../../services/nav_tab_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/home_news_section.dart';
import 'news_list_screen.dart';

/// A published news post: half-article preview, then a choice to read the rest
/// in the app or on TheTradingTitans.com (which is what earns the site its
/// search traffic), and a nudge to practise the market the post is about.
class NewsReaderScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const NewsReaderScreen({super.key, required this.post});

  @override
  State<NewsReaderScreen> createState() => _NewsReaderScreenState();
}

class _NewsReaderScreenState extends State<NewsReaderScreen> {
  bool _expanded = false;

  Map<String, dynamic> get post => widget.post;

  String get _url {
    final slug = (post['slug'] as String? ?? '').trim();
    return slug.isEmpty ? '${AppConstants.marketingSiteUrl}/blog' : '${AppConstants.marketingSiteUrl}/blog/$slug';
  }

  /// Opens the article on the website; copies the link if no browser will take it.
  Future<void> _openFullArticle() async {
    final uri = Uri.tryParse(_url);
    if (uri == null) return;
    try {
      for (final mode in [LaunchMode.externalApplication, LaunchMode.platformDefault, LaunchMode.inAppBrowserView]) {
        if (await launchUrl(uri, mode: mode)) return;
      }
    } catch (_) {}
    await _copyLink();
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
    }
  }

  /// Share without a plugin: WhatsApp's own share link, or copy the article URL.
  void _share() {
    final title = post['title'] as String? ?? 'Market news';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.chat_outlined, color: AppColors.bull),
            title: const Text('Share on WhatsApp'),
            onTap: () async {
              Navigator.pop(sheet);
              final wa = Uri.parse('https://wa.me/?text=${Uri.encodeComponent('$title\n$_url')}');
              if (!await launchUrl(wa, mode: LaunchMode.externalApplication)) await _copyLink();
            },
          ),
          ListTile(
            leading: Icon(Icons.link_rounded, color: AppColors.goldMid),
            title: const Text('Copy link'),
            onTap: () {
              Navigator.pop(sheet);
              _copyLink();
            },
          ),
          ListTile(
            leading: Icon(Icons.open_in_new_rounded, color: AppColors.ink3),
            title: const Text('Open on website'),
            onTap: () {
              Navigator.pop(sheet);
              _openFullArticle();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ]),
      ),
    );
  }

  /// Paragraphs to show: all once expanded, otherwise roughly the first half.
  List<String> _paragraphs(String body) {
    final all = body.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
    if (_expanded) return all;
    if (all.length > 1) return all.take((all.length / 2).ceil()).toList();
    if (body.isEmpty) return const [];
    final cut = (body.length / 2).round();
    final space = body.lastIndexOf(' ', cut);
    return [body.substring(0, space > 0 ? space : cut)];
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseNewsExcerpt(post['excerpt'] as String?);
    final market = parsed.marketKey;
    final tint = newsMarketColors[market] ?? AppColors.goldMid;
    final body = post['body_markdown'] as String? ?? '';
    final published = DateTime.tryParse(post['published_at'] as String? ?? '')?.toLocal();
    // Collapsed always shows about half, so there is more until expanded.
    final hasMore = !_expanded && body.trim().isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
            child: Row(children: [
              AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back to news', onTap: () => Navigator.of(context).pop()),
              const Spacer(),
              AuthIconButton(icon: Icons.share_outlined, label: 'Share article', onTap: _share),
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
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, AppSpacing.xl), children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                _tag((kNewsChipLabels[market] ?? 'Global').toUpperCase(), tint),
                _tag('${newsReadMinutes(body)} MIN READ', null),
              ]),
              const SizedBox(height: AppSpacing.md),
              Text(post['title'] as String? ?? 'Market news', style: GoogleSerif.headline(26).copyWith(height: 1.25)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Trading Titans Desk${published == null ? '' : ' · ${DateFormat('d MMM yyyy').format(published)}'}',
                style: AppFonts.sans(size: 12, color: AppColors.ink4),
              ),
              const SizedBox(height: 18),
              NewsCover(url: post['cover_url'] as String?, market: market, height: 190),
              const SizedBox(height: 18),
              if (parsed.cleanExcerpt.isNotEmpty) ...[
                Text(parsed.cleanExcerpt,
                    style: AppFonts.serif(size: 17, weight: FontWeight.w600, color: AppColors.ink2, height: 1.55)),
                const SizedBox(height: AppSpacing.md),
              ],
              for (final p in _paragraphs(body)) _paragraph(p),
              const SizedBox(height: AppSpacing.md),
              if (hasMore) _continueCard() else _finishedCard(),
              const SizedBox(height: 18),
              _practiseCard(market, tint),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tag(String text, Color? color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(color?.withValues(alpha: 0.14) ?? AppColors.cream),
        child: Text(text, style: AppText.badge.copyWith(color: color ?? AppColors.ink3)),
      );

  /// Markdown subset the editor produces: #/##/### headings, - or * bullets, **bold**.
  Widget _paragraph(String text) {
    final t = text.trim();
    for (final (prefix, size) in [('### ', 18.0), ('## ', 20.0), ('# ', 22.0)]) {
      if (t.startsWith(prefix)) {
        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(t.substring(prefix.length), style: AppFonts.sans(size: size, weight: FontWeight.w700, color: AppColors.ink)),
        );
      }
    }
    if (t.startsWith('- ') || t.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, right: 10),
            child: Container(width: 5, height: 5, decoration: BoxDecoration(color: AppColors.goldMid, shape: BoxShape.circle)),
          ),
          Expanded(child: _rich(t.substring(2))),
        ]),
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: _rich(t));
  }

  Widget _rich(String text) {
    final base = AppFonts.serif(size: 17, color: AppColors.ink, height: 1.6);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in RegExp(r'\*\*(.*?)\*\*').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// Halfway point: finish here or on the website.
  Widget _continueCard() => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.goldPale,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.goldBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Continue reading', style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('Read the rest here, or the full research note with chart levels on TheTradingTitans.com.',
              style: AppFonts.sans(size: 13, color: AppColors.ink3, height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: () => setState(() => _expanded = true),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: const Text('Read the full story here'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _openFullArticle,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open on website'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
        ]),
      );

  Widget _finishedCard() => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.birch),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_outline_rounded, color: AppColors.bull),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text('You have read the full story.', style: AppFonts.sans(size: 14, color: AppColors.ink2))),
          TextButton(onPressed: _openFullArticle, child: const Text('Website')),
        ]),
      );

  /// The design's "practise trade" card. Posts carry a market, not a symbol, so
  /// it practises that market from the Trade tab.
  Widget _practiseCard(String market, Color tint) {
    final name = switch (market) {
      'stock' => 'Indian stocks',
      'us_stock' => 'US stocks',
      'crypto' => 'crypto',
      'pakistan_stock' => 'Pakistan stocks',
      'italy_stock' => 'Italy stocks',
      _ => 'the markets',
    };
    return Material(
      color: AppColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          NavTabService.goToTab(NavTabService.trade);
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Icons.candlestick_chart_outlined, color: tint),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Practise what you just read', style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
                Text('Trade $name with demo cash', style: AppFonts.sans(size: 12, color: AppColors.ink4)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.goldPale,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.goldMid),
              ),
              child: Text('Practise trade', style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.goldMid)),
            ),
          ]),
        ),
      ),
    );
  }
}
