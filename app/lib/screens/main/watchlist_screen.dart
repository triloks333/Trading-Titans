import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/supabase_service.dart';

import '../../widgets/stock_action_sheet.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = SupabaseService();
    final cached = await svc.getCachedWatchlistRaw();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    } else {
      setState(() => _loading = true);
    }

    final raw = await svc.getWatchlistRaw();
    if (mounted) {
      setState(() {
        _items = raw;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Watchlist', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.parchment,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_border, size: 64, color: AppColors.ink4),
                        const SizedBox(height: AppSpacing.md),
                        Text('No items in watchlist', style: GoogleFonts.inter(color: AppColors.ink4)),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Star stocks and crypto to track them here', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink5)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final symbol = item['symbol'] as String? ?? '';
                        final market = item['market'] as String? ?? 'stock';
                        final name = item['name'] as String? ?? symbol;
                        return GestureDetector(
                          onTap: () => StockActionSheet.show(context, symbol: symbol, market: market, name: name, onRefresh: _load),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: AppCard.secondary,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(symbol, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
                                      Text(name, style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Text(market.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink5)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
