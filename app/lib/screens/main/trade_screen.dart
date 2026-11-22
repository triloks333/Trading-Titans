import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/market_hours.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../services/app_flags_service.dart';
import '../../services/currency_service.dart';
import '../../services/market_service.dart';
import '../../services/price_store.dart';
import '../../widgets/price_freshness_note.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/market_nav_bar.dart';
import '../../widgets/stock_action_sheet.dart';
import 'muhurat_screen.dart';
import 'option_chain_screen.dart';
import 'orders_screen.dart';
import 'stock_detail_screen.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/action_reaction_engine.dart';
import '../../services/analytics_service.dart';

typedef MoverSymbol = ({String symbol, String name, String? display});
MoverSymbol _s(String symbol, String name, [String? display]) => (symbol: symbol, name: name, display: display);

/// Headline cards per market: (quote symbol, label). Priced with the rows.
const Map<String, List<(String, String)>> kMarketIndices = {
  'stock': [('NIFTY', 'NIFTY 50'), ('BANKNIFTY', 'BANKNIFTY')],
  'fo': [('NIFTY', 'NIFTY 50'), ('BANKNIFTY', 'BANKNIFTY')],
  'us_stock': [('^GSPC', 'S&P 500'), ('^IXIC', 'NASDAQ')],
  'crypto': [('BTC', 'BTC'), ('ETH', 'ETH')],
  'commodity': [('GC=F', 'GOLD (1g)'), ('CL=F', 'CRUDE')],
  'pakistan_stock': [('^KSE', 'KSE 100')],
  'italy_stock': [('FTSEMIB.MI', 'FTSE MIB')],
};

/// The universe each market's movers are ranked from: the large, liquid names
/// people actually trade. Search reaches everything else. The India, crypto and
/// US lists mirror `POPULAR` in supabase/functions/refresh-quotes so they are
/// served from quotes_cache (pinned by popular_symbols_sync_test).
final Map<String, List<MoverSymbol>> kMoverUniverse = {
  'stock': [
    for (final (s, n) in const [
      ('RELIANCE', 'Reliance Industries'), ('TCS', 'Tata Consultancy Services'), ('HDFCBANK', 'HDFC Bank'),
      ('INFY', 'Infosys'), ('ICICIBANK', 'ICICI Bank'), ('SBIN', 'State Bank of India'), ('BHARTIARTL', 'Bharti Airtel'),
      ('ITC', 'ITC'), ('LT', 'Larsen & Toubro'), ('HINDUNILVR', 'Hindustan Unilever'), ('KOTAKBANK', 'Kotak Mahindra Bank'),
      ('AXISBANK', 'Axis Bank'), ('BAJFINANCE', 'Bajaj Finance'), ('MARUTI', 'Maruti Suzuki'), ('SUNPHARMA', 'Sun Pharma'),
      ('TITAN', 'Titan Company'), ('ASIANPAINT', 'Asian Paints'), ('WIPRO', 'Wipro'), ('HCLTECH', 'HCL Technologies'),
      ('TATASTEEL', 'Tata Steel'), ('NTPC', 'NTPC'), ('POWERGRID', 'Power Grid'), ('ONGC', 'ONGC'),
      ('ADANIENT', 'Adani Enterprises'), ('ETERNAL', 'Eternal (Zomato)'), ('TMPV', 'Tata Motors (Passenger)'),
      ('TMCV', 'Tata Motors (Commercial)'),
    ])
      _s(s, n),
  ],
  'us_stock': [
    for (final (s, n) in const [
      ('AAPL', 'Apple'), ('MSFT', 'Microsoft'), ('NVDA', 'NVIDIA'), ('AMZN', 'Amazon'), ('GOOGL', 'Alphabet'),
      ('META', 'Meta Platforms'), ('TSLA', 'Tesla'), ('NFLX', 'Netflix'), ('AMD', 'AMD'), ('INTC', 'Intel'),
      ('JPM', 'JPMorgan Chase'), ('V', 'Visa'), ('WMT', 'Walmart'), ('DIS', 'Disney'), ('ORCL', 'Oracle'), ('AVGO', 'Broadcom'),
    ])
      _s(s, n),
  ],
  'crypto': [
    for (final (s, n) in const [
      ('BTC', 'Bitcoin'), ('ETH', 'Ethereum'), ('SOL', 'Solana'), ('BNB', 'BNB'), ('XRP', 'Ripple'), ('ADA', 'Cardano'),
      ('DOGE', 'Dogecoin'), ('POL', 'Polygon'), ('AVAX', 'Avalanche'), ('DOT', 'Polkadot'), ('LINK', 'Chainlink'),
      ('TRX', 'Tron'),
    ])
      _s(s, n),
  ],
  // Mirrors COMMODITIES in supabase/functions/_shared/us_market.ts.
  'commodity': [
    _s('GC=F', 'Gold (1g)', 'GOLD'), _s('SI=F', 'Silver (1g)', 'SILVER'), _s('CL=F', 'Crude Oil', 'CRUDE'),
    _s('NG=F', 'Natural Gas', 'NATGAS'), _s('HG=F', 'Copper', 'COPPER'),
  ],
  'pakistan_stock': [
    _s('OGDC.KA', 'Oil & Gas Development Company', 'OGDC'), _s('LUCK.KA', 'Lucky Cement Ltd', 'LUCK'),
    _s('MCB.KA', 'MCB Bank Ltd', 'MCB'), _s('SYS.KA', 'Systems Ltd', 'SYS'), _s('HBL.KA', 'Habib Bank Ltd', 'HBL'),
    _s('EFERT.KA', 'Engro Fertilizers Ltd', 'EFERT'), _s('HUBC.KA', 'Hub Power Company', 'HUBC'),
    _s('FFC.KA', 'Fauji Fertilizer Company', 'FFC'),
  ],
  'italy_stock': [
    _s('ENI.MI', 'Eni S.p.A.', 'ENI'), _s('RACE.MI', 'Ferrari N.V.', 'RACE'), _s('ISP.MI', 'Intesa Sanpaolo', 'ISP'),
    _s('UCG.MI', 'UniCredit S.p.A.', 'UCG'), _s('STLAM.MI', 'Stellantis N.V.', 'STLAM'), _s('ENEL.MI', 'Enel S.p.A.', 'ENEL'),
    _s('G.MI', 'Assicurazioni Generali', 'GENERALI'), _s('PRY.MI', 'Prysmian S.p.A.', 'PRY'),
  ],
};

/// F&O tab: underlyings with an option chain, their name, and the quote that prices them.
const _marketPillIds = {
  'stock': 'trade_market_pill_nse_stock',
  'us_stock': 'trade_market_pill_us_stock',
  'crypto': 'trade_market_pill_crypto',
  'commodity': 'trade_market_pill_commodity',
  'pakistan_stock': 'trade_market_pill_pakistan_psx',
  'italy_stock': 'trade_market_pill_italy_borsa',
  'fo': 'trade_market_pill_nse_fo',
};

const List<(String, String, String)> kFoUnderlyings = [
  ('NIFTY', 'Nifty 50 index', 'NIFTY'), ('BANKNIFTY', 'Nifty Bank index', 'BANKNIFTY'),
  ('RELIANCE', 'Reliance Industries', 'RELIANCE'), ('HDFCBANK', 'HDFC Bank', 'HDFCBANK'), ('ICICIBANK', 'ICICI Bank', 'ICICIBANK'),
  ('INFY', 'Infosys', 'INFY'), ('TCS', 'Tata Consultancy Services', 'TCS'), ('SBIN', 'State Bank of India', 'SBIN'),
];

/// Today's gainers (biggest rise first) or losers (biggest fall first) among
/// [quotes]; flat names belong to neither list.
List<Quote> topMovers(Iterable<Quote> quotes, {required bool gainers, int limit = 8}) {
  final list = quotes.where((q) => gainers ? q.changePct > 0 : q.changePct < 0).toList()
    ..sort((a, b) => gainers ? b.changePct.compareTo(a.changePct) : a.changePct.compareTo(b.changePct));
  return list.take(limit).toList();
}

class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  /// Opens on the user's favourite market; Indian stocks when none was chosen.
  String _market = CurrencyService.instance.defaultMarket;
  String _searchQuery = '';
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _gainers = true;
  Timer? _debounce;

  /// Live prices keyed `symbol\x1Fmarket`, as [MarketService.quotes] returns them.
  /// One batched call per tick prices every card and row on screen.
  Map<String, Quote> _quotes = const {};
  Timer? _priceTimer;

  /// Consecutive failed polls; past two, prices are marked stale so a wedged
  /// feed is visible instead of looking like a flat market.
  int _failedPolls = 0;
  bool get _pricesAreStale => _failedPolls >= 2;

  /// US is visible but greyed until `app_flags.us_stocks_enabled` is on.
  Set<String> get _comingSoonMarkets => AppFlagsService.instance.usStocksEnabled ? const {} : const {'us_stock'};
  bool get _isComingSoon => _comingSoonMarkets.contains(_market);

  /// F&O orders, quotes and chains all run on the `stock` market.
  String get _orderMarket => _market == 'fo' ? 'stock' : _market;
  bool get _searching => _searchQuery.trim().isNotEmpty;

  /// Focused-but-empty search shows the Browse tiles: every market, one tap away.
  late final FocusNode _searchFocus = FocusNode()..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    _checkFirstRunPreferences();
    _refreshPrices();
    // Live pushes redraw the list as prices move. The timer is the fallback for
    // when the socket is down: one batched cache read per market, so 5s is cheap.
    _priceTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPrices());
    PriceStore.instance.addListener(_onPricePush);
  }

  void _onPricePush() => _refreshPrices();

  @override
  void dispose() {
    _debounce?.cancel();
    PriceStore.instance.removeListener(_onPricePush);
    _priceTimer?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _checkFirstRunPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('market_preferences_configured') ?? false) && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMarketPreferencesDialog();
      });
    }
  }

  Future<void> _refreshPrices() async {
    final pairs = _visiblePairs();
    if (pairs.isEmpty) return;
    try {
      final fetched = await MarketService.quotes(pairs);
      if (!mounted) return;
      setState(() {
        // Merge, so a symbol missing from one tick keeps its last price.
        _quotes = {..._quotes, ...fetched};
        _failedPolls = fetched.isEmpty ? _failedPolls + 1 : 0;
      });
    } catch (e) {
      debugPrint('TradeScreen price poll failed: $e');
      if (mounted) setState(() => _failedPolls++);
    }
  }

  /// Everything the current view needs priced: index cards plus the rows.
  List<({String symbol, String market})> _visiblePairs() {
    if (_isComingSoon) return const [];
    final m = _orderMarket;
    return [
      for (final (sym, _) in kMarketIndices[_market] ?? const <(String, String)>[]) (symbol: sym, market: m),
      if (_searching)
        for (final r in _results) (symbol: '${r['symbol'] ?? ''}', market: m)
      else if (_market == 'fo')
        for (final (_, _, q) in kFoUnderlyings) (symbol: q, market: m)
      else
        for (final s in kMoverUniverse[_market] ?? const <MoverSymbol>[]) (symbol: s.symbol, market: m),
    ].where((p) => p.symbol.isNotEmpty).toList();
  }

  Quote? _quote(String symbol) => _quotes['$symbol\x1F$_orderMarket'];

  void _selectMarket(String key) {
    final id = _marketPillIds[key];
    if (id != null) ChurnTelemetryService.instance.recordButtonTap(id);
    if (key == _market) return;
    setState(() {
      _market = key;
      _searchQuery = '';
      _results = [];
      _loading = false;
    });
    _debounce?.cancel();
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
      final results = await MarketService.search(query, _orderMarket);
      if (query != _searchQuery.trim() || !mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      if (results.isEmpty) {
        AnalyticsService.log('telemetry_search_zero_results', {
          'query': query,
          'market': _orderMarket,
        });
        ActionReactionEngine.instance.onZeroResultSearch(query, _orderMarket);
      }
      _refreshPrices();
    } catch (_) {
      if (query != _searchQuery.trim() || !mounted) return;
      setState(() {
        _results = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search failed. Check your connection and try again.')),
      );
    }
  }

  void _openSheet(String symbol, String name) =>
      StockActionSheet.show(context, symbol: symbol, market: _orderMarket, name: name);

  void _openChain(String underlying, double spot) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => OptionChainScreen(underlyingSymbol: underlying, spotPrice: spot)));

  @override
  Widget build(BuildContext context) {
    context.watch<AppFlagsService>(); // US flips out of "coming soon" as the flag lands
    final preferred = context.watch<CurrencyService>().preferredMarkets;
    final tab = MarketTab.byKey(_market);
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
            child: Row(children: [
              Expanded(child: Text('Trade', style: AppFonts.sans(size: 22, weight: FontWeight.w700, color: AppColors.ink))),
              AuthIconButton(icon: Icons.tune_rounded, label: 'Market preferences', onTap: _showMarketPreferencesDialog),
              const SizedBox(width: 8),
              AuthIconButton(
                icon: Icons.format_list_bulleted_rounded,
                label: 'Order book',
                onTap: () {
                  ChurnTelemetryService.instance.recordButtonTap('trade_header_orders_icon_btn');
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
                },
              ),
              const SizedBox(width: 8),
              ListenableBuilder(
                listenable: ThemeService(),
                builder: (_, _) => AuthIconButton(
                  icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  label: 'Toggle light or dark theme',
                  onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
            child: Column(children: [
              if (!_isComingSoon) ...[
                TextField(
                  focusNode: _searchFocus,
                  onTap: () => ChurnTelemetryService.instance.recordButtonTap('trade_search_input_box'),
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  style: AppFonts.sans(size: 14, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: tab.searchHint,
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.ink4),
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              MarketNavBar(
                selectedKey: _market,
                comingSoonKeys: _comingSoonMarkets,
                preferredKeys: preferred,
                filterToPreferred: true,
                onEditPreferred: _showMarketPreferencesDialog,
                onSelected: _selectMarket,
              ),
            ]),
          ),
          if (_isComingSoon)
            Expanded(
              child: EmptyState(
                icon: Icons.public_rounded,
                title: '${tab.label} — coming soon',
                message: 'US market trading is on the way. The tab is here so you can see it land; '
                    'quotes and orders switch on shortly.',
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshPrices,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  children: [
                    if (!_searching && (_market == 'stock' || _market == 'fo')) _muhuratBanner(),
                    if (_searchFocus.hasFocus && !_searching) _browseTiles(),
                    if (!_searching) _indexCards(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.lg, 2, AppSpacing.lg, 6),
                      child: PriceFreshnessNote(),
                    ),
                    ...(_searching ? _searchRows() : _market == 'fo' ? _foRows() : _moverRows()),
                    if (!_searching && _market == 'stock') _chainCard(),
                  ],
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tag(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: AppCard.badge(bg),
        child: Text(text, style: AppText.badge.copyWith(color: fg)),
      );

  /// The next special session (Muhurat) and any exchange holiday in the next two weeks.
  Widget _muhuratBanner() {
    final now = DateTime.now().toUtc();
    final s = MarketHours.nextSpecialSession(now);
    if (s == null) return const SizedBox.shrink();
    final live = !now.isBefore(s.start);
    final left = (live ? s.end : s.start).difference(now);
    final holiday = [for (var d = 1; d <= 14; d++) now.add(Duration(days: d))].where(MarketHours.isIndianHoliday).firstOrNull;
    final gold = AppColors.titanGold;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 12),
      child: Material(
        color: AppColors.titanGoldSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: gold)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MuhuratScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(Icons.local_fire_department_rounded, size: 26, color: gold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(style: AppFonts.sans(size: 13, color: AppColors.ink), children: [
                    TextSpan(text: s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' · ${istLabel(s.start, 'EEE d MMM, h:mm a')} IST'),
                  ])),
                  if (holiday != null)
                    Text('Closed ${istLabel(holiday, 'EEE d MMM')} · exchange holiday',
                        style: AppFonts.sans(size: 11, color: AppColors.ink4)),
                ]),
              ),
              const SizedBox(width: 8),
              _tag(live ? 'LIVE' : '${left.inDays}D ${(left.inHours % 24).toString().padLeft(2, '0')}H',
                  const Color(0xFF1A1200), gold),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _browseTiles() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BROWSE', style: AppText.sectionLabel),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.8,
            children: [
              for (final t in [...MarketTab.all, MarketTab.fo])
                Material(
                  color: AppColors.pureWhite,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () {
                      _searchFocus.unfocus();
                      _selectMarket(t.key);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(children: [
                        Icon(t.icon, size: 20, color: AppColors.goldMid),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      );

  Widget _indexCards() {
    final cards = kMarketIndices[_market] ?? const <(String, String)>[];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(children: [
        for (final (i, (sym, label)) in cards.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _indexCard(sym, label, i == 0 ? 'trade_headline_index_left_card' : 'trade_headline_index_right_card')),
        ],
      ]),
    );
  }

  Widget _indexCard(String sym, String label, String tapId) {
    final q = _quote(sym);
    final up = (q?.change ?? 0) >= 0;
    return Material(
      color: AppColors.pureWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          ChurnTelemetryService.instance.recordButtonTap(tapId);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: sym, market: _orderMarket, name: label)));
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppFonts.sans(size: 12, weight: FontWeight.w600, color: AppColors.ink4)),
            const SizedBox(height: 4),
            Text(q == null ? '—' : Money.instrument(q.price, market: _orderMarket),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.mono(size: 17, weight: FontWeight.w600, color: AppColors.ink)),
            Text(
              q == null ? ' ' : '${up ? '▲ +' : '▼ −'}${q.change.abs().toStringAsFixed(2)} (${q.changePct.abs().toStringAsFixed(2)}%)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.mono(size: 12, color: up ? AppColors.bull : AppColors.bear),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionHead(String label, [Widget? trailing]) => Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 18, AppSpacing.lg, 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
        child: Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: AppText.sectionLabel)),
          ?trailing,
        ]),
      );

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          labelStyle: AppFonts.sans(size: 13, weight: FontWeight.w500, color: on ? AppColors.goldMid : AppColors.ink3),
          side: BorderSide(color: on ? AppColors.goldMid : AppColors.birch),
          onSelected: (_) => onTap(),
        ),
      );

  List<Widget> _moverRows() {
    final universe = kMoverUniverse[_market] ?? const <MoverSymbol>[];
    final bySymbol = {for (final s in universe) s.symbol: s};
    final priced = [for (final s in universe) ?_quote(s.symbol)];
    final movers = topMovers(priced, gainers: _gainers);
    return [
      _sectionHead(
        'Top movers · ${MarketTab.byKey(_market).label}',
        Row(mainAxisSize: MainAxisSize.min, children: [
          _chip('Gainers', _gainers, () {
            ChurnTelemetryService.instance.recordButtonTap('trade_movers_top_gainers_pill');
            setState(() => _gainers = true);
          }),
          _chip('Losers', !_gainers, () {
            ChurnTelemetryService.instance.recordButtonTap('trade_movers_top_losers_pill');
            setState(() => _gainers = false);
          }),
        ]),
      ),
      if (priced.isEmpty)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else if (movers.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(_gainers ? 'Nothing is up today among popular names.' : 'Nothing is down today among popular names.',
              textAlign: TextAlign.center, style: AppText.body),
        )
      else
        for (final q in movers)
          _row(bySymbol[q.symbol]?.display ?? q.symbol, bySymbol[q.symbol]?.name ?? q.name, q,
              () {
            ChurnTelemetryService.instance.recordButtonTap('trade_mover_stock_row_tap', extra: {'sym': q.symbol});
            _openSheet(q.symbol, bySymbol[q.symbol]?.name ?? q.name);
          }),
    ];
  }

  List<Widget> _foRows() => [
        _sectionHead('Option chains · futures'),
        for (final (u, name, sym) in kFoUnderlyings)
          _row(u, name, _quote(sym), () {
            ChurnTelemetryService.instance.recordButtonTap('trade_fo_${u.toLowerCase()}_chain_card', extra: {'sym': u});
            _openChain(u, _quote(sym)?.price ?? 0);
          }),
      ];

  List<Widget> _searchRows() {
    if (_loading) return const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))];
    if (_results.isEmpty) {
      return [
        SizedBox(
          height: 280,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No results',
            message: 'No matches for "${_searchQuery.trim()}" in this market. Try the exchange symbol (e.g. RELIANCE, AAPL, BTC) or switch market above.',
          ),
        ),
      ];
    }
    return [for (final item in _results) _searchRow(item)];
  }

  Widget _searchRow(Map<String, dynamic> item) {
    final symbol = item['symbol'] as String? ?? '';
    final name = item['name'] as String? ?? '';
    // NSE:RELIANCE-EQ reads as RELIANCE.
    var display = item['display_symbol'] as String? ?? symbol;
    if (display == symbol && display.contains(':')) display = display.split(':').last;
    display = display.replaceAll(RegExp(r'-(EQ|SM)$'), '');
    return _row(display, name, _quote(symbol),
        () => _market == 'fo' ? _openChain(display, _quote(symbol)?.price ?? 0) : _openSheet(symbol, name));
  }

  Widget _row(String symbol, String name, Quote? q, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Text(symbol.length >= 2 ? symbol.substring(0, 2) : symbol,
                  style: AppFonts.mono(size: 12, weight: FontWeight.w600, color: AppColors.ink3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(symbol, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodyBold),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 12, color: AppColors.ink4)),
              ]),
            ),
            const SizedBox(width: 8),
            _LivePrice(quote: q, market: _orderMarket, isStale: _pricesAreStale),
          ]),
        ),
      );

  Widget _chainCard() => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Material(
          color: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: AppColors.birch)),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () {
              ChurnTelemetryService.instance.recordButtonTap('trade_fo_nifty_chain_card', extra: {'sym': 'NIFTY'});
              _openChain('NIFTY', _quote('NIFTY')?.price ?? 0);
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.show_chart_rounded, color: AppColors.goldMid),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Option chain · NIFTY', style: AppText.bodyBold),
                    Text('Practise F&O with live greeks', style: AppFonts.sans(size: 12, color: AppColors.ink4)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
              ]),
            ),
          ),
        ),
      );

  Future<void> _showMarketPreferencesDialog() async {
    final current = CurrencyService.instance.preferredMarkets;
    final selected = List<String>.from(current.isEmpty ? ['stock', 'us_stock', 'crypto'] : current);

    const marketOptions = [
      {'key': 'stock', 'title': 'Indian stock market', 'desc': 'NSE & BSE Equities, F&O'},
      {'key': 'us_stock', 'title': 'US stocks', 'desc': 'NYSE & NASDAQ Equities'},
      {'key': 'crypto', 'title': 'Cryptocurrency', 'desc': 'Major crypto pairs & perpetuals'},
      {'key': 'commodity', 'title': 'Commodities', 'desc': 'Gold, silver, crude oil, gas, copper'},
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
                        // Own Material so the tick's ink isn't hidden under the tinted box.
                        child: Material(
                          type: MaterialType.transparency,
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
                            if (_market != 'fo' && !selected.contains(_market)) {
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
              style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isStale ? AppColors.ink4 : AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${isPositive ? '▲ +' : '▼ −'}${q.changePct.abs().toStringAsFixed(2)}%',
          style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isPositive ? AppColors.bull : AppColors.bear,
          ),
        ),
      ],
    );
  }
}
