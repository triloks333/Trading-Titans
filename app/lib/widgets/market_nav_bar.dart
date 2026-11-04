import 'package:flutter/material.dart';
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

  /// Titan Terminal segmented control: equal segments, every label visible.
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(children: [
          for (final tab in orderedTabs) Expanded(child: _buildTab(tab, tab.key == selectedKey)),
        ]),
      );

  Widget _buildTab(MarketTab tab, bool selected) {
    final comingSoon = comingSoonKeys.contains(tab.key);
    final label = comingSoon ? '${tab.label}, coming soon' : tab.label;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true, // the visible label would otherwise be read twice
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(tab.key),
        child: AnimatedContainer(
          duration: _animation,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.pureWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: selected ? Border.all(color: AppColors.birch) : null,
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tab.label,
                  style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: selected ? AppColors.ink : AppColors.ink3)),
              if (comingSoon) ...[
                const SizedBox(width: 4),
                Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.titanGold, shape: BoxShape.circle)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
