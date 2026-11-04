import 'package:flutter/material.dart';

import '../core/theme.dart';

/// News markets as tagged in `blog_posts.excerpt` (`[market:crypto] ...`).
/// Shared with NewsListScreen, which filters on the same keys.
const Map<String, String> newsMarketLabels = {
  'all': 'Global Markets',
  'stock': 'Indian Stocks',
  'us_stock': 'US Stocks',
  'crypto': 'Crypto',
  'pakistan_stock': 'Pakistan Stocks',
  'italy_stock': 'Italy Stocks',
};

/// A getter so the colours follow the active theme instead of freezing at first read.
Map<String, Color> get newsMarketColors => {
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
