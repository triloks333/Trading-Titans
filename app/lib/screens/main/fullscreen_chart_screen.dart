import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../widgets/instrument_chart.dart';
import 'order_entry_screen.dart';

class FullscreenChartScreen extends StatefulWidget {
  final String symbol;
  final String market;
  final String name;
  final Quote? quote;

  const FullscreenChartScreen({
    super.key,
    required this.symbol,
    required this.market,
    required this.name,
    this.quote,
  });

  @override
  State<FullscreenChartScreen> createState() => _FullscreenChartScreenState();
}

class _FullscreenChartScreenState extends State<FullscreenChartScreen> {
  Key _chartKey = UniqueKey();
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    // Force portrait orientation matching the user's reference image
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    // Restore standard default orientations on exit
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _toggleOrientation() {
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    });
  }

  void _navigateToOrder(bool isBuy) async {
    if (widget.quote == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderEntryScreen(
          quote: widget.quote!,
          isBuy: isBuy,
        ),
      ),
    );
  }

  void _refreshChart() {
    setState(() {
      _chartKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        scrolledUnderElevation: 0.5,
        leadingWidth: 48,
        leading: IconButton(
          icon:       Icon(Icons.close_rounded, color: AppColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Row(
            children: [
              // Search-bar lookalike
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                            Icon(Icons.search_rounded, size: 16, color: AppColors.ink4),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'eg: ${widget.symbol.toLowerCase()} bse',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppColors.ink4,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Watchlist selector
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                          Icon(Icons.chevron_left_rounded, size: 16, color: AppColors.ink),
                    Text(
                      'Watchlist 1',
                      style: GoogleFonts.inter(
                        color: AppColors.ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                          Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.ink),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: InstrumentChart(
        key: _chartKey,
        symbol: widget.symbol,
        market: widget.market,
        theme: 'light',
        livePrice: widget.quote?.price,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon:       Icon(Icons.close_rounded, color: AppColors.ink),
                onPressed: () => Navigator.of(context).pop(),
              ),
              IconButton(
                icon:       Icon(Icons.refresh_rounded, color: AppColors.ink),
                onPressed: _refreshChart,
              ),
              TextButton.icon(
                icon: Icon(
                  _isLandscape ? Icons.screen_lock_portrait_rounded : Icons.screen_rotation_rounded,
                  color: AppColors.ink,
                  size: 18,
                ),
                label: Text(
                  _isLandscape ? 'Portrait' : 'Landscape',
                  style: GoogleFonts.inter(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _toggleOrientation,
              ),
              const Spacer(),
              // Buy (B) Button
              GestureDetector(
                onTap: widget.quote != null ? () => _navigateToOrder(true) : null,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB), // Premium Groww/Zerodha Blue
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'B',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Sell (S) Button
              GestureDetector(
                onTap: widget.quote != null ? () => _navigateToOrder(false) : null,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626), // Premium Groww/Zerodha Red
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'S',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
