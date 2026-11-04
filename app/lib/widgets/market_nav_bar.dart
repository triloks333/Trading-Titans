import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// One selectable market in the trade screen's market bar.
class MarketTab {
  /// Value stored on `orders.market` / `holdings.market`.
  final String key;
  final String label;
  final IconData icon;

  /// Hint shown under the search field.
  final String searchHint;

  /// Heading above the default (non-search) list.
  final String popularHeading;

  const MarketTab({
    required this.key,
    required this.label,
    required this.icon,
    required this.searchHint,
    required this.popularHeading,
  });

  static const stock = MarketTab(
    key: 'stock',
    label: 'India',
    icon: Icons.currency_rupee,
    searchHint: 'Search NSE stocks...',
    popularHeading: 'POPULAR STOCKS',
  );

  static const usStock = MarketTab(
    key: 'us_stock',
    label: 'US Stocks',
    icon: Icons.attach_money,
    searchHint: 'Search US stocks...',
    popularHeading: 'POPULAR US STOCKS',
  );

  static const crypto = MarketTab(
    key: 'crypto',
    label: 'Crypto',
    icon: Icons.currency_bitcoin,
    searchHint: 'Search crypto...',
    popularHeading: 'POPULAR CRYPTO',
  );

  static const pakistanStock = MarketTab(
    key: 'pakistan_stock',
    label: 'Pakistan',
    icon: Icons.account_balance,
    searchHint: 'Search PSX stocks...',
    popularHeading: 'POPULAR PAKISTAN STOCKS',
  );

  static const italyStock = MarketTab(
    key: 'italy_stock',
    label: 'Italy',
    icon: Icons.euro,
    searchHint: 'Search Milan stocks...',
    popularHeading: 'POPULAR ITALY STOCKS',
  );

  static const List<MarketTab> all = [
    stock,
    usStock,
    crypto,
    pakistanStock,
    italyStock,
  ];

  static MarketTab byKey(String key) =>
      all.firstWhere((t) => t.key == key, orElse: () => stock);
}

/// Horizontal market selector where the active tab expands to icon + label and
/// the inactive ones collapse to icon only.
class MarketNavBar extends StatelessWidget {
  const MarketNavBar({
    super.key,
    required this.selectedKey,
    required this.onSelected,
    this.comingSoonKeys = const {},
    this.preferredKeys = const [],
    this.filterToPreferred = false,
  });

  final String selectedKey;
  final ValueChanged<String> onSelected;

  /// Tabs that are visible but not wired to live data yet.
  final Set<String> comingSoonKeys;

  /// Markets the user chose in their preferences (maximum 3).
  final List<String> preferredKeys;

  /// When true, limits visible tabs to only the user's preferred markets (max 3),
  /// keeping the trade screen clean and uncluttered.
  final bool filterToPreferred;

  static const Duration _animation = Duration(milliseconds: 200);

  /// Preferred markets first, each group keeping canonical order. When
  /// [filterToPreferred] is true, returns only the preferred markets (max 3).
  List<MarketTab> get orderedTabs {
    if (filterToPreferred) {
      if (preferredKeys.isEmpty) return MarketTab.all.take(3).toList();
      final filtered = MarketTab.all.where((t) => preferredKeys.contains(t.key)).toList();
      return filtered.isEmpty ? MarketTab.all.take(3).toList() : filtered.take(3).toList();
    }
    if (preferredKeys.isEmpty) return MarketTab.all;
    final preferred = MarketTab.all.where((t) => preferredKeys.contains(t.key));
    final rest = MarketTab.all.where((t) => !preferredKeys.contains(t.key));
    return [...preferred, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: AppCard.cream,
      child: Row(
        children: [
          for (final tab in orderedTabs)
            _buildTab(context, tab, tab.key == selectedKey),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, MarketTab tab, bool selected) {
    final comingSoon = comingSoonKeys.contains(tab.key);
    final color = selected ? AppColors.ink : AppColors.ink4;

    final content = AnimatedContainer(
      duration: _animation,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.pureWhite : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: selected ? AppShadows.sm : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(tab.icon, size: 18, color: color),
          // Only the active tab shows its label; the rest stay icon-only.
          if (selected) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
          if (comingSoon) ...[
            const SizedBox(width: 4),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.imperialGold,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );

    final semanticLabel = comingSoon ? '${tab.label}, coming soon' : tab.label;

    final tappable = Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(tab.key),
          child: content,
        ),
      ),
    );

    // The active tab takes the leftover width; collapsed tabs stay intrinsic so
    // three tabs still fit on a narrow (320dp) screen.
    return selected ? Expanded(child: tappable) : tappable;
  }
}
