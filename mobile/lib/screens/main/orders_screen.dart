import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
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

  @override
  void initState() {
    super.initState();
    _ordersFuture = _supabase.getOrders();
  }

  Future<void> _cancel(String id) async {
    await _supabase.cancelOrder(id);
    setState(() => _ordersFuture = _supabase.getOrders());
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
              return Container(
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
                              Text(order.symbol, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.ink)),
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
                        Text('${order.quantity} @ ₹${order.price.toStringAsFixed(0)}', style: GoogleFonts.inter(color: AppColors.ink3)),
                        Text('Total: ₹${order.total.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppColors.ink)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(order.createdAt?.toLocal().toString() ?? '', style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                        if (order.isPending)
                          GestureDetector(
                            onTap: () => _cancel(order.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.bear),
                                borderRadius: BorderRadius.circular(AppRadius.tag),
                              ),
                              child: Text('Cancel', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.bear)),
                            ),
                          ),
                      ],
                    ),
                  ],
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
}
