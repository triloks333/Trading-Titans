import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/market_service.dart';
import '../../models/quote.dart';

import '../../widgets/stock_action_sheet.dart';
import 'package:google_fonts/google_fonts.dart';

class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  String _market = 'stock';
  String _searchQuery = '';
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;

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
    {'symbol': 'MATIC', 'name': 'Polygon'},
  ];

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
    final results = await MarketService.search(query, _market);
    if (query != _searchQuery.trim()) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final popularList = _market == 'stock' ? _popularStocks : _popularCrypto;
    final displayList = _searchQuery.trim().isEmpty ? popularList.map((e) => e).toList() : _results;

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
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: AppCard.cream,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() { _market = 'stock'; _searchQuery = ''; _results = []; }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _market == 'stock' ? AppColors.pureWhite : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            boxShadow: _market == 'stock' ? AppShadows.sm : null,
                          ),
                          child: Text(
                            'Indian Stocks',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: _market == 'stock' ? AppColors.ink : AppColors.ink4),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() { _market = 'crypto'; _searchQuery = ''; _results = []; }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _market == 'crypto' ? AppColors.pureWhite : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            boxShadow: _market == 'crypto' ? AppShadows.sm : null,
                          ),
                          child: Text(
                            'Crypto',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: _market == 'crypto' ? AppColors.ink : AppColors.ink4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(AppSpacing.lg),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: AppCard.primary,
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: AppColors.ink4),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: _market == 'stock' ? 'Search NSE stocks...' : 'Search crypto...',
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
                  _market == 'stock' ? 'POPULAR STOCKS' : 'TOP CRYPTO',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink4, letterSpacing: 0.5),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: displayList.length,
                      itemBuilder: (context, index) {
                        final item = displayList[index];
                        final symbol = item['symbol'] as String? ?? '';
                        final name = item['name'] as String? ?? '';
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
                                    symbol.length >= 2 ? symbol.substring(0, 2) : symbol,
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.goldDeep),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(symbol, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
                                      const SizedBox(height: 2),
                                      Text(name, style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                  _LivePriceWidget(symbol: symbol, market: _market),
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

class _LivePriceWidget extends StatefulWidget {
  final String symbol;
  final String market;
  const _LivePriceWidget({required this.symbol, required this.market});

  @override
  State<_LivePriceWidget> createState() => _LivePriceWidgetState();
}

class _LivePriceWidgetState extends State<_LivePriceWidget> {
  Quote? _quote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _LivePriceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol || oldWidget.market != widget.market) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final q = await MarketService.quote(widget.symbol, widget.market);
    if (mounted) {
      setState(() {
        _quote = q;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_quote == null) {
      return const Icon(Icons.chevron_right, size: 18, color: AppColors.ink4);
    }
    final isPositive = _quote!.change >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '₹${_quote!.price.toStringAsFixed(2)}',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          '${isPositive ? '+' : ''}${_quote!.changePct.toStringAsFixed(2)}%',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isPositive ? AppColors.bull : AppColors.bear),
        ),
      ],
    );
  }
}
