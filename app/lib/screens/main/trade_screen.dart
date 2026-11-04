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
import 'package:shared_preferences/shared_preferences.dart';

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

  final List<Map<String, String>> _popularPakistanStocks = [
    {'symbol': 'OGDC.KA', 'name': 'Oil & Gas Development Company', 'display_symbol': 'OGDC'},
    {'symbol': 'LUCK.KA', 'name': 'Lucky Cement Ltd', 'display_symbol': 'LUCK'},
    {'symbol': 'MCB.KA', 'name': 'MCB Bank Ltd', 'display_symbol': 'MCB'},
    {'symbol': 'SYS.KA', 'name': 'Systems Ltd', 'display_symbol': 'SYS'},
    {'symbol': 'HBL.KA', 'name': 'Habib Bank Ltd', 'display_symbol': 'HBL'},
    {'symbol': 'EFERT.KA', 'name': 'Engro Fertilizers Ltd', 'display_symbol': 'EFERT'},
    {'symbol': 'HUBC.KA', 'name': 'Hub Power Company', 'display_symbol': 'HUBC'},
    {'symbol': 'FFC.KA', 'name': 'Fauji Fertilizer Company', 'display_symbol': 'FFC'},
  ];

  final List<Map<String, String>> _popularItalyStocks = [
    {'symbol': 'ENI.MI', 'name': 'Eni S.p.A.', 'display_symbol': 'ENI'},
    {'symbol': 'RACE.MI', 'name': 'Ferrari N.V.', 'display_symbol': 'RACE'},
    {'symbol': 'ISP.MI', 'name': 'Intesa Sanpaolo', 'display_symbol': 'ISP'},
    {'symbol': 'UCG.MI', 'name': 'UniCredit S.p.A.', 'display_symbol': 'UCG'},
    {'symbol': 'STLAM.MI', 'name': 'Stellantis N.V.', 'display_symbol': 'STLAM'},
    {'symbol': 'ENEL.MI', 'name': 'Enel S.p.A.', 'display_symbol': 'ENEL'},
    {'symbol': 'G.MI', 'name': 'Assicurazioni Generali', 'display_symbol': 'GENERALI'},
    {'symbol': 'PRY.MI', 'name': 'Prysmian S.p.A.', 'display_symbol': 'PRY'},
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
    _checkFirstRunPreferences();
    _refreshPrices();
    _priceTimer = Timer.periodic(
      AppConstants.dashboardPricePoll,
      (_) => _refreshPrices(),
    );
  }

  Future<void> _checkFirstRunPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getBool('market_preferences_configured') ?? false;
    if (!configured && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMarketPreferencesDialog();
      });
    }
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
        'pakistan_stock' => _popularPakistanStocks,
        'italy_stock' => _popularItalyStocks,
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trade', style: GoogleFonts.ibmPlexSans(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('Real markets. Virtual stakes.', style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink4)),
                    ],
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: AppColors.ink),
                    color: AppColors.pureWhite,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(color: AppColors.birch),
                    ),
                    onSelected: (val) {
                      if (val == 'preferences') {
                        _showMarketPreferencesDialog();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'preferences',
                        child: Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 18, color: AppColors.ink),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Change Market Preferences',
                              style: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: MarketNavBar(
                selectedKey: _market,
                comingSoonKeys: _comingSoonMarkets,
                preferredKeys: context.watch<CurrencyService>().preferredMarkets,
                filterToPreferred: true,
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
                          hintStyle: GoogleFonts.ibmPlexSans(color: AppColors.ink5),
                          border: InputBorder.none,
                        ),
                        style: GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink),
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
                    style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink4, letterSpacing: 0.5),
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
                                    style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.goldDeep),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displaySymbol, style: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
                                      const SizedBox(height: 2),
                                      Text(name, style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4), maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Future<void> _showMarketPreferencesDialog() async {
    final current = CurrencyService.instance.preferredMarkets;
    final selected = List<String>.from(current.isEmpty ? ['stock', 'us_stock', 'crypto'] : current);

    const marketOptions = [
      {'key': 'stock', 'title': 'Indian stock market', 'desc': 'NSE & BSE Equities, F&O'},
      {'key': 'us_stock', 'title': 'US stocks', 'desc': 'NYSE & NASDAQ Equities'},
      {'key': 'crypto', 'title': 'Cryptocurrency', 'desc': 'Major crypto pairs & perpetuals'},
      {'key': 'pakistan_stock', 'title': 'Pakistan stocks', 'desc': 'Pakistan Stock Exchange (PSX)'},
      {'key': 'italy_stock', 'title': 'Italy stocks', 'desc': 'Borsa Italiana (Milan)'},
    ];

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.pureWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: AppColors.birch),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.goldPale,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.tune_rounded, color: AppColors.goldDeep, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Market Preferences',
                          style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose up to 3 markets to trade. You can change your choice anytime from the 3 dots menu.',
                    style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppColors.ink4, height: 1.4),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: marketOptions.map((opt) {
                      final key = opt['key']!;
                      final isChecked = selected.contains(key);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isChecked ? AppColors.goldPale.withValues(alpha: 0.4) : AppColors.cream,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isChecked ? AppColors.imperialGold : AppColors.birch,
                            width: isChecked ? 1.5 : 1.0,
                          ),
                        ),
                        child: CheckboxListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          dense: true,
                          activeColor: AppColors.imperialGold,
                          checkColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(
                            opt['title']!,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          subtitle: Text(
                            opt['desc']!,
                            style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4),
                          ),
                          value: isChecked,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                if (selected.length >= 3) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('You can select a maximum of 3 markets at a time.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                selected.add(key);
                              } else {
                                if (selected.length > 1) {
                                  selected.remove(key);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please select at least 1 market.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selected.isNotEmpty
                        ? () async {
                            Navigator.of(ctx).pop();
                            await CurrencyService.instance.setPreferredMarkets(selected);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('market_preferences_configured', true);
                            if (!selected.contains(_market)) {
                              setState(() {
                                _market = selected.first;
                                _searchQuery = '';
                                _results = [];
                              });
                            }
                            _refreshPrices();
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.imperialGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      'Save Preferences (${selected.length}/3)',
                      style: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
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
              style: GoogleFonts.ibmPlexSans(
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
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isPositive ? AppColors.bull : AppColors.bear,
          ),
        ),
      ],
    );
  }
}
