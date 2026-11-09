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

  static const commodity = MarketTab(
    key: 'commodity',
    label: 'Commodities',
    icon: Icons.diamond_outlined,
    searchHint: 'Search gold, silver, crude...',
    popularHeading: 'COMMODITIES',
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
    commodity,
    pakistanStock,
    italyStock,
  ];

  /// Indian derivatives: option chains and futures. Not a separate order
  /// market (F&O orders still carry `stock`), so it is never in [all].
  static const fo = MarketTab(
    key: 'fo',
    label: 'F&O',
    icon: Icons.stacked_line_chart,
    searchHint: 'Search an underlying, e.g. NIFTY',
    popularHeading: 'OPTION CHAINS',
  );

  static MarketTab byKey(String key) =>
      [...all, fo].firstWhere((t) => t.key == key, orElse: () => stock);
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
    this.onEditPreferred,
  });

  /// Opens the "pick your 3 markets" editor; offered at the top of the More sheet.
  final VoidCallback? onEditPreferred;

  final String selectedKey;
  final ValueChanged<String> onSelected;

  /// Tabs that are visible but not wired to live data yet.
  final Set<String> comingSoonKeys;

  /// Markets the user chose in their preferences (maximum 3).
  final List<String> preferredKeys;

  /// When true, the bar shows only the user's preferred markets (max 3) plus a
  /// More segment; every other market, F&O included, lives in the More sheet.
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

  /// Markets behind the More segment: everything not on the bar, then F&O.
  List<MarketTab> get overflowTabs {
    if (!filterToPreferred) return const [];
    final shown = orderedTabs.map((t) => t.key).toSet();
    return [...MarketTab.all.where((t) => !shown.contains(t.key)), MarketTab.fo];
  }

  /// Titan Terminal segmented control: equal segments, every label visible.
  @override
  Widget build(BuildContext context) {
    final overflow = overflowTabs;
    // An overflow market that is open takes the More segment's label, so the bar
    // always says where you are.
    final pickedOverflow = overflow.where((t) => t.key == selectedKey).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(children: [
        for (final tab in orderedTabs) Expanded(child: _buildTab(tab, tab.key == selectedKey)),
        if (overflow.isNotEmpty)
          Expanded(
            child: _buildTab(
              MarketTab(
                key: 'more',
                label: '${pickedOverflow?.label ?? 'More'} ▾',
                icon: Icons.expand_more_rounded,
                searchHint: '',
                popularHeading: '',
              ),
              pickedOverflow != null,
              onTap: () => _openMore(context, overflow),
            ),
          ),
      ]),
    );
  }

  Future<void> _openMore(BuildContext context, List<MarketTab> overflow) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: AppColors.pureWhite,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text('More markets', style: AppFonts.sans(size: 16, weight: FontWeight.w600, color: AppColors.ink)),
              trailing: onEditPreferred == null
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.pop(sheet);
                        onEditPreferred!();
                      },
                      child: const Text('Edit my 3'),
                    ),
            ),
            for (final tab in overflow)
              ListTile(
                leading: Icon(tab.icon, color: AppColors.goldMid),
                title: Text(tab.label, style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
                selected: tab.key == selectedKey,
                onTap: () {
                  Navigator.pop(sheet);
                  onSelected(tab.key);
                },
              ),
            const SizedBox(height: 8),
          ]),
        ),
      );

  Widget _buildTab(MarketTab tab, bool selected, {VoidCallback? onTap}) {
    final comingSoon = comingSoonKeys.contains(tab.key);
    final label = comingSoon ? '${tab.label}, coming soon' : tab.label;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true, // the visible label would otherwise be read twice
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => onSelected(tab.key),
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
