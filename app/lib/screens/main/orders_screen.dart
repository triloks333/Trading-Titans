import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/money.dart';
import '../../core/market_hours.dart';
import '../../models/order.dart';
import '../../models/quote.dart' as app_models;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../services/nav_tab_service.dart';
import 'package:google_fonts/google_fonts.dart';

class OrdersScreen extends StatefulWidget {
  /// When true, the screen renders only its body (no Scaffold/AppBar) so it can
  /// be embedded inside another screen such as a portfolio tab.
  final bool embedded;

  const OrdersScreen({super.key, this.embedded = false});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final SupabaseService _supabase = SupabaseService();
  late Future<List<Order>> _ordersFuture;
  RealtimeChannel? _ordersSubscription;

  /// A single day rarely runs long, but an active F&O session can, and silently
  /// truncating a day the user explicitly asked for would misrepresent history.
  static const int _dayLimit = 200;

  /// The IST calendar day on screen. Defaults to today so the page opens on the
  /// current session rather than an ever-growing all-time list.
  DateTime _selectedIstDate = MarketHours.istDate();

  bool get _isToday => _selectedIstDate == MarketHours.istDate();

  /// Earliest selectable day: the account's creation date, since no order can
  /// predate it. Falls back to a fixed floor before the app existed (the first
  /// migration is May 2026) when the timestamp cannot be read.
  DateTime get _firstSelectableDate {
    final createdAt = _supabase.client.auth.currentUser?.createdAt;
    final parsed = DateTime.tryParse(createdAt ?? '');
    return MarketHours.istDate(parsed ?? DateTime.utc(2026, 1, 1));
  }

  String get _dateLabel {
    final today = MarketHours.istDate();
    if (_selectedIstDate == today) return 'Today';
    if (_selectedIstDate == DateTime.utc(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    return DateFormat('dd MMM yyyy').format(_selectedIstDate);
  }

  /// The one place the list is (re)loaded, so every path — first build,
  /// pull-to-refresh, retry, cancel, modify, and the realtime subscription —
  /// stays on the selected day instead of silently falling back to all-time.
  /// Call inside `setState`.
  void _reload() {
    _ltpSignature = ''; // force fresh LTPs for the new set
    _ordersFuture =
        _supabase.getOrders(onIstDate: _selectedIstDate, limit: _dayLimit);
  }

  void _goToDate(DateTime istDate) {
    setState(() {
      _selectedIstDate = istDate;
      _reload();
    });
  }

  /// Steps [days] from the selected day, clamped to the selectable range.
  /// `DateTime.utc` normalises month/year rollover.
  void _shiftDay(int days) {
    final target = DateTime.utc(
        _selectedIstDate.year, _selectedIstDate.month, _selectedIstDate.day + days);
    if (target.isAfter(MarketHours.istDate())) return;
    if (target.isBefore(_firstSelectableDate)) return;
    _goToDate(target);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedIstDate,
      firstDate: _firstSelectableDate,
      lastDate: MarketHours.istDate(),
      helpText: 'Select order date',
    );
    if (picked == null || !mounted) return;
    // showDatePicker returns a local DateTime; re-key it as a UTC date so it
    // compares equal to MarketHours.istDate().
    _goToDate(DateTime.utc(picked.year, picked.month, picked.day));
  }

  // Batched LTP cache for the visible orders. Instead of each row firing its
  // own quote request (an N+1), we fetch the unique symbols once into this map
  // and every row reads from it. The signature guards against re-fetching the
  // same set on every rebuild.
  Map<String, app_models.Quote?> _ltp = {};
  String _ltpSignature = '';

  String _ltpKey(Order o) => '${o.symbol}\u001f${o.market}';

  Future<void> _prefetchLtps(List<Order> orders) async {
    final pairs = <String, Order>{};
    for (final o in orders) {
      pairs[_ltpKey(o)] = o;
    }
    final signature = (pairs.keys.toList()..sort()).join(',');
    if (signature == _ltpSignature) return; // this exact set is already loaded
    _ltpSignature = signature;

    final results = <String, app_models.Quote?>{};
    await Future.wait(pairs.entries.map((e) async {
      try {
        results[e.key] = await _supabase.getQuote(e.value.symbol, e.value.market,
            expiryDate: e.value.expiryDate);
      } catch (_) {
        results[e.key] = null;
      }
    }));
    if (mounted) setState(() => _ltp = results);
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _subscribeToOrders();
  }

  void _subscribeToOrders() {
    final user = _supabase.currentUser;
    if (user == null) return;

    _ordersSubscription = _supabase.client
        .channel('public:orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            if (mounted) setState(_reload);
          },
        );
    _ordersSubscription?.subscribe();
  }

  @override
  void dispose() {
    if (_ordersSubscription != null) {
      _supabase.client.removeChannel(_ordersSubscription!);
    }
    super.dispose();
  }

  Future<void> _cancel(String id) async {
    try {
      await _supabase.cancelOrder(id);
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order cancelled successfully'),
            backgroundColor: AppColors.bull,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel order: $e'),
            backgroundColor: AppColors.bear,
          ),
        );
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'executed': return AppColors.bull;
      case 'pending': return AppColors.imperialGold;
      case 'cancelled': return AppColors.ink4;
      default: return AppColors.ink4;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildOrdersBody();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Order History', style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: _buildOrdersBody(),
    );
  }

  Widget _buildOrdersBody() {
    return Column(
      children: [
        _buildDateBar(),
        Expanded(child: _buildOrdersList()),
      ],
    );
  }

  /// Day selector: arrows for stepping, the label itself opens a picker for
  /// jumping. Deliberately sits outside the [FutureBuilder] so an empty or
  /// failed day can still be navigated away from.
  Widget _buildDateBar() {
    final canGoBack = _selectedIstDate.isAfter(_firstSelectableDate);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        border: Border(bottom: BorderSide(color: AppColors.birch)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      child: Row(
        children: [
          IconButton(
            onPressed: canGoBack ? () => _shiftDay(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.ink3,
            tooltip: 'Previous day',
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Showing orders for $_dateLabel. Tap to change date.',
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(AppRadius.tag),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 14, color: AppColors.ink4),
                      const SizedBox(width: 6),
                      Text(
                        _dateLabel,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _isToday ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppColors.ink3,
            tooltip: 'Next day',
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    return FutureBuilder<List<Order>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ListSkeleton();
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: "We couldn't load your orders. Check your connection and try again.",
              onRetry: () => setState(_reload),
            );
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            // A past day with no trades is normal, not an onboarding moment, so
            // it offers a way back to today instead of a "start trading" CTA.
            return EmptyState(
              icon: Icons.receipt_long_rounded,
              title: _isToday ? 'No orders today' : 'No orders on $_dateLabel',
              message: _isToday
                  ? 'Your placed, pending, and executed orders will appear here.'
                  : 'Nothing was traded on this day. Use the arrows above to look at another day.',
              actionLabel: _isToday ? 'Start trading' : 'Back to today',
              onAction: _isToday
                  ? () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      NavTabService.goToTab(NavTabService.trade);
                    }
                  : () => _goToDate(MarketHours.istDate()),
            );
          }
          // Batch-fetch all visible orders' LTPs once (kills the per-row N+1).
          WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchLtps(orders));
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _ordersFuture;
            },
            child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemBuilder: (context, index) {
              final order = orders[index];
              final isBuy = order.isBuy;
              return InkWell(
                onTap: () => _showOrderDetails(context, order),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: AppCard.secondary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: AppCard.badge(isBuy ? AppColors.bullLight : AppColors.bearLight),
                                  child: Text(
                                    order.side.toUpperCase(),
                                    style: GoogleFonts.ibmPlexSans(fontSize: 10, fontWeight: FontWeight.bold, color: isBuy ? AppColors.bull : AppColors.bear, letterSpacing: 0.5),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    order.symbol,
                                    style: GoogleFonts.ibmPlexSans(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.ink,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: AppCard.badge(_statusColor(order.status).withValues(alpha: 0.15)),
                            child: Text(
                              order.status.toUpperCase(),
                              style: GoogleFonts.ibmPlexSans(fontSize: 10, fontWeight: FontWeight.bold, color: _statusColor(order.status), letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${Money.quantity(order.quantity, market: order.market)} @ ${Money.instrument(order.displayPrice, market: order.market)}', style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], color: AppColors.ink3)),
                              const SizedBox(height: 2),
                              _buildLtpWidget(order),
                            ],
                          ),
                          Text('Total: ${Money.instrument(order.displayTotal, market: order.market)}', style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: FontWeight.w600, color: AppColors.ink)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(order.createdAt?.toLocal().toString().split('.').first ?? '', style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontSize: 12)),
                          if (order.isPending)
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => _showModifyOrderSheet(context, order),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.imperialGold,
                                    side: BorderSide(color: AppColors.imperialGold, width: 1),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: const Size(64, 32),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.tag),
                                    ),
                                  ),
                                  child: Text(
                                    'Edit',
                                    style: GoogleFonts.ibmPlexSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => _cancel(order.id),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.bear,
                                    side: BorderSide(color: AppColors.bear, width: 1),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: const Size(64, 32),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.tag),
                                    ),
                                  ),
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.ibmPlexSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemCount: orders.length,
            ),
          );
        },
      );
  }

  void _showOrderDetails(BuildContext context, Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isBuy = order.isBuy;
        final statusColor = _statusColor(order.status);
        final localizedCreated = order.createdAt?.toLocal().toString().split('.').first ?? 'N/A';
        final localizedExecuted = order.executedAt?.toLocal().toString().split('.').first ?? 'N/A';
        
        return Container(
          decoration:       BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.birch,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.symbol,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            color: AppColors.ink4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isBuy ? AppColors.bullLight : AppColors.bearLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          order.side.toUpperCase(),
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isBuy ? AppColors.bull : AppColors.bear,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          order.status.toUpperCase(),
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
                    Divider(color: AppColors.birch, height: 1),
              const SizedBox(height: 24),
              _buildDetailGrid([
                _buildGridItem('Quantity', order.quantity.toStringAsFixed(order.market == 'crypto' ? 4 : 0)),
                // A resting order's number is a trigger, not a traded price.
                // Labelling both "Price" is what let an unfilled limit order
                // read as a missed fill when the LTP sat the wrong side of it.
                _buildGridItem(
                  order.isPending && order.displayLimitPrice != null ? 'Limit Price' : 'Price',
                  Money.instrument(
                    order.isPending ? (order.displayLimitPrice ?? order.displayPrice) : order.displayPrice,
                    market: order.market,
                  ),
                ),
                _buildLtpGridItem(order),
                _buildGridItem('Total Value', Money.instrument(order.displayTotal, market: order.market)),
                _buildGridItem('Instrument', (order.instrumentType ?? 'EQUITY').toUpperCase()),
                _buildGridItem('Order Type', (order.orderType ?? 'market').toUpperCase()),
                // Net, not gross. This tile used to show the raw `realized_pnl`
                // column while the portfolio's closed-position card showed the
                // same trade net of charges, so the two screens disagreed on the
                // same number. The full arithmetic is broken out in the charges
                // box below.
                _buildGridItem('Realized P&L (net)', Money.wallet(order.netRealizedPnl, decimals: 2),
                    valueColor: order.netRealizedPnl > 0
                        ? AppColors.bull
                        : order.netRealizedPnl < 0
                            ? AppColors.bear
                            : AppColors.ink),
                _buildGridItem('Placed At', localizedCreated),
                _buildGridItem('Executed At', order.isExecuted ? localizedExecuted : '--'),
              ]),
              if (order.totalCharges > 0) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 15, color: AppColors.ink3),
                              const SizedBox(width: 6),
                              Text(
                                'Transaction Charges',
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'VIRTUAL CASH',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFE65100),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Order value line
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${Money.quantity(order.quantity, market: order.market)} × ${Money.instrument(order.displayPrice, market: order.market)}',
                            style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink2,
                            ),
                          ),
                          Text(
                            Money.instrument(order.displayTotal, market: order.market),
                            style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(height: 0.5, color: AppColors.birch),
                      const SizedBox(height: 10),
                      _buildChargeRow('Brokerage', Money.wallet(order.brokerage, decimals: 2)),
                      const SizedBox(height: 8),
                      _buildChargeRow('Stamp Duty', Money.wallet(order.stampDuty, decimals: 2)),
                      const SizedBox(height: 8),
                      _buildChargeRow('Taxes & Exchange Fees', Money.wallet(order.taxCharges, decimals: 2)),
                      const SizedBox(height: 12),
                      Divider(color: AppColors.birch, height: 1),
                      const SizedBox(height: 12),
                      _buildChargeRow(
                        'Total Charges',
                        Money.wallet(order.totalCharges, decimals: 2),
                        isTotal: true,
                      ),
                    ],
                  ),
                ),
                // The money box: gross, then charges, then net, so the number on
                // the tile above can be checked by eye.
                //
                // What used to be here was a single sentence, "Charges reduced
                // your return by X%", computed as totalCharges / realizedPnl. Two
                // things were wrong with it. The denominator was gross P&L, so a
                // ₹1 profit against ₹20 of brokerage announced "2000.0%". And it
                // read as though it covered the whole trade when it only ever had
                // the charges on THIS order -- the entry leg's brokerage, stamp
                // duty and GST sit on a different row. Showing the arithmetic is
                // both more useful and honest about its scope.
                if (order.realizedPnl != 0.0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: order.netRealizedPnl >= 0
                          ? AppColors.bullLight.withValues(alpha: 0.3)
                          : AppColors.bearLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: order.netRealizedPnl >= 0
                            ? AppColors.bull.withValues(alpha: 0.2)
                            : AppColors.bear.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              order.netRealizedPnl >= 0
                                  ? Icons.trending_up_rounded
                                  : Icons.trending_down_rounded,
                              color: order.netRealizedPnl >= 0 ? AppColors.bull : AppColors.bear,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'How this P&L is calculated',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildChargeRow(
                          'Gross P&L on this order',
                          Money.signedWallet(order.realizedPnl, decimals: 2),
                        ),
                        const SizedBox(height: 8),
                        _buildChargeRow(
                          'Less: charges on this order',
                          '-${Money.wallet(order.totalCharges, decimals: 2)}',
                        ),
                        const SizedBox(height: 12),
                        Divider(color: AppColors.birch, height: 1),
                        const SizedBox(height: 12),
                        _buildChargeRow(
                          'Net P&L on this order',
                          Money.signedWallet(order.netRealizedPnl, decimals: 2),
                          isTotal: true,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          order.isBuy
                              ? 'Charges shown are for this order only.'
                              : 'Charges shown are for this exit order only. The entry order was charged separately when it was placed, so a full round trip costs more than the figure above.',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 11,
                            color: AppColors.ink4,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              Divider(color: AppColors.birch, height: 1),
              const SizedBox(height: 20),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: order.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order ID copied to clipboard')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Row(
                    children: [
                            Icon(Icons.fingerprint_rounded, size: 18, color: AppColors.ink4),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Order ID: ${order.id}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: AppColors.ink3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                            Icon(Icons.copy_rounded, size: 16, color: AppColors.ink4),
                    ],
                  ),
                ),
              ),
              if (order.isPending) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showModifyOrderSheet(context, order);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.imperialGold,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'EDIT ORDER',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _cancel(order.id);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.bear,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'CANCEL ORDER',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLtpWidget(Order order) {
    final quote = _ltp[_ltpKey(order)];
    if (!_ltp.containsKey(_ltpKey(order))) {
      return Text('LTP: Loading...', style: GoogleFonts.ibmPlexSans(fontSize: 11, color: AppColors.ink4));
    }
    if (quote == null) return const SizedBox.shrink();
    final isPositive = quote.changePct >= 0;
    return Text(
      'LTP: ${Money.instrument(quote.price, market: quote.market)} (${isPositive ? "+" : ""}${quote.changePct.toStringAsFixed(2)}%)',
      style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: isPositive ? AppColors.bull : AppColors.bear,
      ),
    );
  }

  Widget _buildLtpGridItem(Order order) {
    final quote = _ltp[_ltpKey(order)];
    if (!_ltp.containsKey(_ltpKey(order))) {
      return _buildGridItem('Current Price (LTP)', 'Loading...');
    }
    if (quote == null) return _buildGridItem('Current Price (LTP)', '--');
    final isPositive = quote.changePct >= 0;
    return _buildGridItem(
      'Current Price (LTP)',
      Money.instrument(quote.price, market: quote.market),
      valueColor: isPositive ? AppColors.bull : AppColors.bear,
    );
  }

  void _showModifyOrderSheet(BuildContext context, Order order) {
    final qtyController = TextEditingController(text: order.quantity.toStringAsFixed(order.market == 'crypto' ? 4 : 0));
    final priceController = TextEditingController(
        text: Money.bare(order.displayPrice, from: Money.sourceFor(order.market)));
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isBuy = order.side == 'buy';
        final color = isBuy ? AppColors.bull : AppColors.bear;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration:       BoxDecoration(
                  color: AppColors.pureWhite,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Modify Order: ${order.symbol}',
                              style: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                            ),
                            Text(
                              '${order.side.toUpperCase()} • ${(order.orderType ?? "limit").toUpperCase()}',
                              style: GoogleFonts.ibmPlexSans(color: AppColors.ink4, fontSize: 12),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              labelStyle: GoogleFonts.ibmPlexSans(color: AppColors.ink3),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Limit Price',
                              labelStyle: GoogleFonts.ibmPlexSans(color: AppColors.ink3),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final newQty = double.tryParse(qtyController.text);
                                final newPrice = double.tryParse(priceController.text);
                                if (newQty == null || newQty <= 0 || newPrice == null || newPrice <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter valid quantity and price')),
                                  );
                                  return;
                                }

                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(sheetCtx);

                                setSheetState(() => isSubmitting = true);
                                try {
                                  await _supabase.modifyOrder(
                                    orderId: order.id,
                                    quantity: newQty,
                                    price: newPrice,
                                    isLimit: (order.orderType ?? 'limit') == 'limit',
                                  );
                                  if (mounted) {
                                    setState(_reload);
                                    navigator.pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Order modified successfully'),
                                        backgroundColor: AppColors.bull,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to modify order: $e'),
                                      backgroundColor: AppColors.bear,
                                    ),
                                  );
                                } finally {
                                  setSheetState(() => isSubmitting = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                                'MODIFY ${order.side.toUpperCase()} ORDER',
                                style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailGrid(List<Widget> children) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: children.map((c) => SizedBox(width: 160, child: c)).toList(),
    );
  }

  Widget _buildGridItem(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            color: AppColors.ink4,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildChargeRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: isTotal ? 13 : 12,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            color: isTotal ? AppColors.ink : AppColors.ink3,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
            fontSize: isTotal ? 13 : 12,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: isTotal ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ],
    );
  }
}
