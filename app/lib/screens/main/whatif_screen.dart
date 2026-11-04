import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../services/market_service.dart';
import '../../widgets/empty_state.dart';
import 'package:intl/intl.dart';

class WhatIfScreen extends StatefulWidget {
  const WhatIfScreen({super.key});

  @override
  State<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends State<WhatIfScreen> {
  String _symbol = 'RELIANCE';
  String _market = 'stock';
  bool _busy = false;
  Map<String, dynamic>? _result;

  late final TextEditingController _amountController;
  late final TextEditingController _yearsController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: '10000');
    _yearsController = TextEditingController(text: '3');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _yearsController.dispose();
    super.dispose();
  }

  Future<void> _runSimulation() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final amount = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0.0;
    final years = int.tryParse(_yearsController.text) ?? 1;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid investment amount')),
      );
      setState(() => _busy = false);
      return;
    }

    if (years <= 0 || years > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter years between 1 and 10')),
      );
      setState(() => _busy = false);
      return;
    }

    final result = await MarketService.simulateWhatIf(_symbol, _market, amount, years);
    if (mounted) {
      setState(() {
        _result = result;
        _busy = false;
      });
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load simulation. Please verify the symbol and try again.')),
        );
      }
    }
  }

  void _showAssetSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AssetSearchBottomSheet(
        market: _market,
        onSelected: (symbol, name) {
          setState(() {
            _symbol = symbol;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('What-If Simulator', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: AppColors.birch),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'If I had invested in… how much would I have today?',
                    style: GoogleFonts.ibmPlexSans(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(children: [
                    _segmentButton('stock'),
                    const SizedBox(width: AppSpacing.sm),
                    _segmentButton('crypto'),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  
                  // Symbol Selector Field
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Symbol', style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpacing.xs),
                      InkWell(
                        onTap: _showAssetSearchSheet,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.cream,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.birch),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _symbol,
                                style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
                              ),
                                    Icon(Icons.arrow_drop_down, color: AppColors.ink3),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: AppSpacing.md),
                  _inputField('Amount (${Money.symbol})', _amountController, TextInputType.number),
                  const SizedBox(height: AppSpacing.md),
                  _inputField('Years Ago', _yearsController, TextInputType.number),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _runSimulation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.imperialGold,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _busy
                          ?       SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2))
                          : Text('Calculate', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_result != null) () {
              DateTime? purchaseDate;
              try {
                purchaseDate = DateTime.parse(_result!['purchase_date'] as String).toLocal();
              } catch (_) {}

              return Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.warmWhite,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.birch),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Result for ${_result!['symbol']}',
                      style: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Invested ${Money.wallet((_result!['amount_invested'] as num), decimals: 0)}',
                      style: GoogleFonts.ibmPlexSans(color: AppColors.ink4),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Current value ${Money.wallet((_result!['current_value'] as num), decimals: 0)}',
                      style: GoogleFonts.ibmPlexSans(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'P&L ${(_result!['pnl'] as num) >= 0 ? '+' : ''}${Money.wallet((_result!['pnl'] as num), decimals: 0)}',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: (_result!['pnl'] as num) >= 0 ? AppColors.bull : AppColors.bear,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Units held ${(_result!['units'] as num).toStringAsFixed(4)}',
                      style: GoogleFonts.ibmPlexSans(color: AppColors.ink4),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      purchaseDate != null
                          ? 'Simulated purchase price on ${DateFormat('dd MMM yyyy').format(purchaseDate)}: ${Money.wallet((_result!['purchase_price'] as num), decimals: 2)}'
                          : 'Simulated purchase price: ${Money.wallet((_result!['purchase_price'] as num), decimals: 2)}',
                      style: GoogleFonts.ibmPlexSans(color: AppColors.ink4),
                    ),
                    if (_market == 'crypto') ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '*Calculated using the ${_result!['symbol']}-INR pair on Yahoo Finance.',
                        style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              );
            }(),
          ],
        ),
      ),
    );
  }

  Widget _segmentButton(String value) {
    final selected = _market == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _market = value;
            _symbol = value == 'stock' ? 'RELIANCE' : 'BTC';
            _result = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.pureWhite : AppColors.cream,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.birch),
          ),
          child: Text(
            value.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSans(
              color: selected ? AppColors.ink : AppColors.ink4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController controller, TextInputType keyboardType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.ibmPlexSans(fontSize: 16, color: AppColors.ink, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: label,
            filled: true,
            fillColor: AppColors.cream,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:       BorderSide(color: AppColors.birch),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:       BorderSide(color: AppColors.birch),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.imperialGold),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _AssetSearchBottomSheet extends StatefulWidget {
  final String market;
  final void Function(String symbol, String name) onSelected;

  const _AssetSearchBottomSheet({
    required this.market,
    required this.onSelected,
  });

  @override
  State<_AssetSearchBottomSheet> createState() => _AssetSearchBottomSheetState();
}

class _AssetSearchBottomSheetState extends State<_AssetSearchBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
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
    {'symbol': 'ZOMATO', 'name': 'Zomato'},
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

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    setState(() {
      _loading = val.trim().isNotEmpty;
    });
    if (val.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(val.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await MarketService.search(query, widget.market);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
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
  Widget build(BuildContext context) {
    final popularList = widget.market == 'stock' ? _popularStocks : _popularCrypto;
    final displayList = _searchController.text.trim().isEmpty ? popularList : _results;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration:       BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.birch,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select ${widget.market == 'stock' ? 'Stock' : 'Crypto'}',
                  style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                ),
                IconButton(
                  icon:       Icon(Icons.close, color: AppColors.ink3),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.birch),
            ),
            child: Row(
              children: [
                      Icon(Icons.search, size: 18, color: AppColors.ink4),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: widget.market == 'stock' ? 'Search NSE stocks...' : 'Search crypto...',
                      hintStyle: GoogleFonts.ibmPlexSans(color: AppColors.ink5),
                      border: InputBorder.none,
                    ),
                    style: GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_searchController.text.trim().isNotEmpty && displayList.isEmpty)
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No results',
                        message: 'No matches for "${_searchController.text.trim()}". Try a different name or symbol.',
                      )
                    : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final item = displayList[index];
                      final symbol = item['symbol'] as String? ?? '';
                      final name = item['name'] as String? ?? '';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: Container(
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
                            style: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.goldDeep),
                          ),
                        ),
                        title: Text(
                          symbol,
                          style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        subtitle: Text(
                          name,
                          style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          widget.onSelected(symbol, name);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
