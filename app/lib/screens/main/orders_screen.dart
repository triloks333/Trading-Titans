import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/quote.dart' as app_models;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'package:google_fonts/google_fonts.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final SupabaseService _supabase = SupabaseService();
  late Future<List<Order>> _ordersFuture;
  RealtimeChannel? _ordersSubscription;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _supabase.getOrders();
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
            if (mounted) {
              setState(() {
                _ordersFuture = _supabase.getOrders();
              });
            }
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
        setState(() => _ordersFuture = _supabase.getOrders());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Order History', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.parchment,
        centerTitle: false,
      ),
      body: FutureBuilder<List<Order>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load orders: ${snapshot.error}'));
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return Center(child: Text('No orders yet', style: GoogleFonts.inter(color: AppColors.ink4)));
          }
          return ListView.separated(
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
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isBuy ? AppColors.bull : AppColors.bear, letterSpacing: 0.5),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    order.symbol,
                                    style: GoogleFonts.inter(
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
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: _statusColor(order.status), letterSpacing: 0.5),
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
                              Text('${order.quantity.toStringAsFixed(order.market == 'crypto' ? 4 : 0)} @ ₹${order.price.toStringAsFixed(2)}', style: GoogleFonts.inter(color: AppColors.ink3)),
                              const SizedBox(height: 2),
                              _buildLtpWidget(order),
                            ],
                          ),
                          Text('Total: ₹${order.total.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.ink)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(order.createdAt?.toLocal().toString().split('.').first ?? '', style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                          if (order.isPending)
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => _showModifyOrderSheet(context, order),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.imperialGold,
                                    side: const BorderSide(color: AppColors.imperialGold, width: 1),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: const Size(64, 32),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.tag),
                                    ),
                                  ),
                                  child: Text(
                                    'Edit',
                                    style: GoogleFonts.inter(
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
                                    side: const BorderSide(color: AppColors.bear, width: 1),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    minimumSize: const Size(64, 32),
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.tag),
                                    ),
                                  ),
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.inter(
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
          );
        },
      ),
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
        final totalValue = order.total;
        
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
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.name,
                          style: GoogleFonts.inter(
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
                          style: GoogleFonts.inter(
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
                          style: GoogleFonts.inter(
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
                _buildGridItem('Price', '₹${order.price.toStringAsFixed(2)}'),
                _buildLtpGridItem(order),
                _buildGridItem('Total Value', '₹${totalValue.toStringAsFixed(2)}'),
                _buildGridItem('Instrument', (order.instrumentType ?? 'EQUITY').toUpperCase()),
                _buildGridItem('Order Type', (order.orderType ?? 'market').toUpperCase()),
                _buildGridItem('Realized P&L', '₹${order.realizedPnl.toStringAsFixed(2)}', 
                    valueColor: order.realizedPnl > 0 
                        ? AppColors.bull 
                        : order.realizedPnl < 0 
                            ? AppColors.bear 
                            : AppColors.ink),
                _buildGridItem('Placed At', localizedCreated),
                _buildGridItem('Executed At', order.isExecuted ? localizedExecuted : '--'),
              ]),
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
                          style: GoogleFonts.inter(
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
                          style: GoogleFonts.inter(
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
                          style: GoogleFonts.inter(
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
    return FutureBuilder<app_models.Quote?>(
      future: _supabase.getQuote(order.symbol, order.market),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('LTP: Loading...', style: GoogleFonts.inter(fontSize: 11, color: AppColors.ink4));
        }
        final quote = snapshot.data;
        if (quote == null) return const SizedBox.shrink();
        final isPositive = quote.changePct >= 0;
        return Text(
          'LTP: ₹${quote.price.toStringAsFixed(2)} (${isPositive ? "+" : ""}${quote.changePct.toStringAsFixed(2)}%)',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isPositive ? AppColors.bull : AppColors.bear,
          ),
        );
      },
    );
  }

  Widget _buildLtpGridItem(Order order) {
    return FutureBuilder<app_models.Quote?>(
      future: _supabase.getQuote(order.symbol, order.market),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildGridItem('Current Price (LTP)', 'Loading...');
        }
        final quote = snapshot.data;
        if (quote == null) return _buildGridItem('Current Price (LTP)', '--');
        final isPositive = quote.changePct >= 0;
        return _buildGridItem(
          'Current Price (LTP)',
          '₹${quote.price.toStringAsFixed(2)}',
          valueColor: isPositive ? AppColors.bull : AppColors.bear,
        );
      },
    );
  }

  void _showModifyOrderSheet(BuildContext context, Order order) {
    final qtyController = TextEditingController(text: order.quantity.toStringAsFixed(order.market == 'crypto' ? 4 : 0));
    final priceController = TextEditingController(text: order.price.toStringAsFixed(2));
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
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink),
                            ),
                            Text(
                              '${order.side.toUpperCase()} • ${(order.orderType ?? "limit").toUpperCase()}',
                              style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12),
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
                              labelStyle: GoogleFonts.inter(color: AppColors.ink3),
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
                              labelStyle: GoogleFonts.inter(color: AppColors.ink3),
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
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _ordersFuture = _supabase.getOrders();
                                    });
                                    navigator.pop();
                                    messenger.showSnackBar(
                                      const SnackBar(
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
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
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
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppColors.ink4,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.ink,
          ),
        ),
      ],
    );
  }
}
