import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../core/app_constants.dart';
import '../../services/market_service.dart';
import '../../models/quote.dart';

import '../../widgets/stock_action_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/market_nav_bar.dart';
import '../../services/app_flags_service.dart';
import '../../services/currency_service.dart';
import 'package:google_fonts/google_fonts.dart';

class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  /// Opens on the user's favourite market. Falls back to Indian stocks, which is
  /// also the default for an account that never answered onboarding.
  String _market = CurrencyService.instance.defaultMarket;
  String _searchQuery = '';
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;

  /// Live prices for whatever the list is currently showing, keyed
  /// `symbol\x1Fmarket` to match [MarketService.quotes].
  ///
  /// Held here rather than in each row because one batched call per tick costs a
  /// single `quotes_cache` query for the whole list, where per-row polling cost
  /// one query *plus* a live fetch per row per tick. With nine popular rows on a
  /// 4s poll that was roughly 4.5 requests a second from one phone.
  Map<String, Quote> _quotes = const {};
  Timer? _priceTimer;

  /// Consecutive failed polls. Rows show a stale marker past
  /// [_staleAfterFailures] so a wedged feed is visible instead of looking like a
  /// price that simply is not moving.
  int _failedPolls = 0;
  static const int _staleAfterFailures = 2;

  bool get _pricesAreStale => _failedPolls >= _staleAfterFailures;

  final List<Map<String, String>> _popularStocks = [
    {'symbol': 'RELIANCE', 'name': 'Reliance Industries'},
    {'symbol': 'TCS', 'name': 'Tata Consultancy Services'},
    {'symbol': 'HDFCBANK', 'name': 'HDFC Bank'},
    {'symbol': 'INFY', 'name': 'Infosys'},
    {'symbol': 'ICICIBANK', 'name': 'ICICI Bank'},
    {'symbol': 'TMCV', 'name': 'Tata Motors (Commercial)'},
    {'symbol': 'TMPV', 'name': 'Tata Motors (Passenger)'},
    {'symbol': 'ADANIENT', 'name': 'Adani Enterprises'},
    {'symbol': 'ETERNAL', 'name': 'Eternal (Zomato)'},
  ];

  final List<Map<String, String>> _popularCrypto = [
    {'symbol': 'BTC', 'name': 'Bitcoin'},
    {'symbol': 'ETH', 'name': 'Ethereum'},
    {'symbol': 'SOL', 'name': 'Solana'},
    {'symbol': 'BNB', 'name': 'BNB'},
    {'symbol': 'XRP', 'name': 'Ripple'},
    {'symbol': 'ADA', 'name': 'Cardano'},
    {'symbol': 'DOGE', 'name': 'Dogecoin'},
    {'symbol': 'POL', 'name': 'Polygon'},
  ];

  final List<Map<String, String>> _popularUsStocks = [
    {'symbol': 'AAPL', 'name': 'Apple'},
    {'symbol': 'MSFT', 'name': 'Microsoft'},
    {'symbol': 'NVDA', 'name': 'NVIDIA'},
    {'symbol': 'AMZN', 'name': 'Amazon'},
    {'symbol': 'GOOGL', 'name': 'Alphabet'},
    {'symbol': 'META', 'name': 'Meta Platforms'},
    {'symbol': 'TSLA', 'name': 'Tesla'},
    {'symbol': 'NFLX', 'name': 'Netflix'},
  ];

  /// Markets that are visible in the bar but not wired to live quotes yet.
  /// Driven by the `us_stocks_enabled` flag in the `app_flags` table, so US
  /// stocks can be switched on from the backend without a release.
  Set<String> get _comingSoonMarkets =>
      AppFlagsService.instance.usStocksEnabled ? const {} : const {'us_stock'};

  bool get _isComingSoon => _comingSoonMarkets.contains(_market);

  @override
  void initState() {
    super.initState();
    _refreshPrices();
    _priceTimer = Timer.periodic(
      AppConstants.dashboardPricePoll,
      (_) => _refreshPrices(),
    );
  }

  /// Fetches every visible row's price in one call.
  ///
  /// Deliberately keeps the previous prices on failure — a row that was working a
  /// moment ago should not blank — but counts the failure so the UI can say so.
  Future<void> _refreshPrices() async {
    final pairs = _visiblePairs();
    if (pairs.isEmpty) return;
    try {
      final fetched = await MarketService.quotes(pairs);
      if (!mounted) return;
      setState(() {
        // Merge rather than replace: a symbol missing from this tick keeps its
        // last known price instead of flickering back to a spinner.
        _quotes = {..._quotes, ...fetched};
        _failedPolls = fetched.isEmpty ? _failedPolls + 1 : 0;
      });
    } catch (e) {
      debugPrint('TradeScreen price poll failed: $e');
      if (mounted) setState(() => _failedPolls++);
    }
  }

  /// The symbol/market pairs currently on screen.
  List<({String symbol, String market})> _visiblePairs() {
    if (_isComingSoon) return const [];
    final source = _searchQuery.trim().isEmpty ? _popularFor(_market) : _results;
    return source
        .map((e) => (symbol: '${e['symbol'] ?? ''}', market: _market))
        .where((p) => p.symbol.isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _popularFor(String market) => switch (market) {
        'crypto' => _popularCrypto,
        'us_stock' => _popularUsStocks,
        _ => _popularStocks,
      };

  void _selectMarket(String key) {
    if (key == _market) return;
    setState(() {
      _market = key;
      _searchQuery = '';
      _results = [];
      _loading = false;
    });
    _debounce?.cancel();
    // The new market's symbols have no prices yet, so fetch without waiting for
    // the next tick.
    _refreshPrices();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(val.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await MarketService.search(query, _market);
      if (query != _searchQuery.trim() || !mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      // Search results are a different symbol set, so price them immediately
      // rather than showing spinners until the next tick.
      _refreshPrices();
    } catch (_) {
      if (query != _searchQuery.trim() || !mounted) return;
      setState(() {
        _results = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search failed. Check your connection and try again.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _priceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched so the US tab flips out of "coming soon" as soon as the flag
    // lands, without needing a screen change.
    context.watch<AppFlagsService>();
    final tab = MarketTab.byKey(_market);
    final displayList = _searchQuery.trim().isEmpty
        ? _popularFor(_market)
        : _results;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trade', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text('Real markets. Virtual stakes.', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: MarketNavBar(
                selectedKey: _market,
                comingSoonKeys: _comingSoonMarkets,
                // Preferred markets come first, but every market stays visible:
                // hiding one would strand any position the user already holds.
                preferredKeys: context.watch<CurrencyService>().preferredMarkets,
                onSelected: _selectMarket,
              ),
            ),
            if (!_isComingSoon) ...[
              Container(
                margin: const EdgeInsets.all(AppSpacing.lg),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: AppCard.primary,
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: AppColors.ink4),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: tab.searchHint,
                          hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                          border: InputBorder.none,
                        ),
                        style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
              if (_searchQuery.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    tab.popularHeading,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink4, letterSpacing: 0.5),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (_isComingSoon)
              Expanded(
                child: EmptyState(
                  icon: Icons.public_rounded,
                  title: '${tab.label} — coming soon',
                  message:
                      'US market trading is on the way. The tab is here so you can '
                      'see it land; quotes and orders switch on shortly.',
                ),
              )
            else
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_searchQuery.trim().isNotEmpty && displayList.isEmpty)
                      ? EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No results',
                          message: 'No matches for "${_searchQuery.trim()}". Try a different name or symbol.',
                        )
                      : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: displayList.length,
                      itemBuilder: (context, index) {
                        final item = displayList[index];
                        final symbol = item['symbol'] as String? ?? '';
                        final name = item['name'] as String? ?? '';
                        // Use display_symbol for cleaner UI (without NSE: and -EQ)
                        var displaySymbol = item['display_symbol'] as String? ?? symbol;
                        // Fallback: strip NSE:/BSE: prefix for display if not provided
                        if (displaySymbol == symbol && displaySymbol.contains(':')) {
                          displaySymbol = displaySymbol.split(':').last;
                        }
                        // Strip -EQ suffix for display
                        displaySymbol = displaySymbol.replaceAll(RegExp(r'-(EQ|SM)$'), '');
                        return GestureDetector(
                          onTap: () => StockActionSheet.show(context, symbol: symbol, market: _market, name: name),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: AppCard.secondary,
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.goldPale,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.goldBorder),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    displaySymbol.length >= 2 ? displaySymbol.substring(0, 2) : displaySymbol,
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.goldDeep),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displaySymbol, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
                                      const SizedBox(height: 2),
                                      Text(name, style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                  _LivePrice(
                                    quote: _quotes['$symbol\x1F$_market'],
                                    market: _market,
                                    isStale: _pricesAreStale,
                                  ),
                                ],
                              ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders one row's price. Stateless: the screen owns fetching, so there is no
/// per-row timer to leak and every row on screen shows the same tick.
class _LivePrice extends StatelessWidget {
  final Quote? quote;
  final String market;

  /// True when the last few polls failed. Dims the figure and shows a dot, so a
  /// wedged feed is distinguishable from a price that is genuinely flat.
  final bool isStale;

  const _LivePrice({
    required this.quote,
    required this.market,
    required this.isStale,
  });

  @override
  Widget build(BuildContext context) {
    final q = quote;
    if (q == null) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final isPositive = q.change >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isStale) ...[
              Tooltip(
                message: 'Price is not updating — check your connection',
                child: Icon(Icons.cloud_off_rounded,
                    size: 11, color: AppColors.ink5),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              Money.instrument(q.price, market: market),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isStale ? AppColors.ink4 : AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${isPositive ? '+' : ''}${q.changePct.toStringAsFixed(2)}%',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isPositive ? AppColors.bull : AppColors.bear,
          ),
        ),
      ],
    );
  }
}
