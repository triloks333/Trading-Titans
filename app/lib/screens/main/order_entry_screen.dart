import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/analytics_service.dart';
import '../../services/fo_instruments_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/swipe_button.dart';
import '../../widgets/info_tooltip.dart';
import 'wallet_screen.dart';

class OrderEntryScreen extends StatefulWidget {
  final Quote quote;
  final bool isBuy;
  final String instrumentType;
  final double? strikePrice;
  final String? optionType;
  final String? expiryDate;
  final double? prefilledQuantity;
  final bool isExitOrder; // true when launched from portfolio Exit button
  final double? marginUsed; // capital blocked for F&O positions (for disclaimer)

  const OrderEntryScreen({
    super.key,
    required this.quote,
    required this.isBuy,
    this.instrumentType = 'EQUITY',
    this.strikePrice,
    this.optionType,
    this.expiryDate,
    this.prefilledQuantity,
    this.isExitOrder = false,
    this.marginUsed,
  });

  @override
  State<OrderEntryScreen> createState() => _OrderEntryScreenState();
}

class _OrderEntryScreenState extends State<OrderEntryScreen> {
  late final TextEditingController _qtyController;
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _triggerPriceController = TextEditingController();
  final TextEditingController _disclosedQtyController = TextEditingController(text: '0');
  final TextEditingController _moneyController = TextEditingController();
  
  bool _isMarket = true;
  bool _isIntraday = true;
  bool _isStoploss = false;
  bool _isMarketProtection = false;
  bool _inputByMoney = false; // false = quantity mode, true = money mode
  
  bool _isAdvancedOpen = false;
  String _validity = 'DAY';
  
  bool _isLoading = false;
  Map<String, dynamic>? _existingHolding;

  /// Real-market lot size for F&O contracts (e.g. RELIANCE = 500, NIFTY = 75).
  /// Loaded asynchronously from the instruments table. Defaults to 1 until
  /// loaded (and stays 1 for equities/crypto which trade in single units).
  int _foLotSize = 1;

  bool get _isCrypto => widget.quote.market == 'crypto';

  bool get _isDerivative =>
      widget.instrumentType == 'OPTION' || widget.instrumentType == 'FUTURE';

  @override
  void initState() {
    super.initState();
    _loadHolding();
    _loadLotSize();

    double initialQty = 1.0;
    if (widget.prefilledQuantity != null) {
      if (_isDerivative) {
        // prefilledQuantity is the position's total units (lots * lotSize).
        // The real lot size loads asynchronously in _loadLotSize(), which then
        // recomputes this field into whole lots. Start from the raw value.
        initialQty = widget.prefilledQuantity!;
      } else {
        initialQty = widget.prefilledQuantity!;
      }
    }
    
    final qtyStr = _isCrypto 
        ? initialQty.toString() 
        : initialQty.toInt().toString();

    _priceController.text = widget.quote.price.toStringAsFixed(2);
    _qtyController = TextEditingController(text: qtyStr);
    _qtyController.addListener(_updateState);
    _priceController.addListener(_updateState);
    _moneyController.addListener(_updateState);
  }

  /// Fetches the real-market lot size for the contract and, for exit/prefilled
  /// flows, converts the prefilled total-unit quantity back into whole lots.
  Future<void> _loadLotSize() async {
    if (!_isDerivative) return;
    try {
      final ls = await FoInstrumentsService().getLotSize(widget.quote.symbol);
      if (!mounted || ls <= 0) return;
      setState(() {
        _foLotSize = ls;
        if (widget.prefilledQuantity != null) {
          final lots = (widget.prefilledQuantity! / ls).round();
          _qtyController.text = (lots < 1 ? 1 : lots).toString();
        }
      });
    } catch (_) {
      // Keep the default lot size of 1 on failure; order can still proceed.
    }
  }

  Future<void> _loadHolding() async {
    try {
      final user = SupabaseService().currentUser;
      if (user == null) return;
      
      Map<String, dynamic>? existing;
      if (widget.instrumentType == 'OPTION' || widget.instrumentType == 'FUTURE') {
        final res = await SupabaseService().client
            .from('fo_positions')
            .select()
            .eq('user_id', user.id)
            .eq('symbol', widget.quote.symbol)
            .eq('instrument_type', widget.instrumentType)
            .eq('is_settled', false)
            .maybeSingle();
        if (res != null) {
          existing = Map<String, dynamic>.from(res as Map);
        }
      } else {
        final res = await SupabaseService().client
            .from('holdings')
            .select()
            .eq('user_id', user.id)
            .eq('symbol', widget.quote.symbol)
            .eq('market', widget.quote.market)
            .maybeSingle();
        if (res != null) {
          existing = Map<String, dynamic>.from(res as Map);
        }
      }
      
      if (mounted && existing != null) {
        setState(() {
          _existingHolding = existing;
        });
      }
    } catch (_) {
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _triggerPriceController.dispose();
    _disclosedQtyController.dispose();
    _moneyController.dispose();
    super.dispose();
  }

  void _updateState() {
    setState(() {});
  }

  double get _quantityValue {
    if (_inputByMoney && _isCrypto) {
      final money = double.tryParse(_moneyController.text) ?? 0.0;
      if (_price > 0) return money / _price;
      return 0.0;
    }
    if (_isCrypto) {
      return double.tryParse(_qtyController.text) ?? 0.0;
    }
    return (int.tryParse(_qtyController.text) ?? 0).toDouble();
  }

  int get _lotSize {
    if (_isDerivative) {
      return _foLotSize; // real-market lot size loaded from instruments table
    }
    return 1;
  }

  double get _price {
    if (_isMarket) return widget.quote.price;
    return double.tryParse(_priceController.text) ?? widget.quote.price;
  }

  double get _marginRequired {
    // Exit orders (closing existing positions) never require new capital
    if (widget.isExitOrder) return 0.0;

    if (_inputByMoney && _isCrypto) {
      return double.tryParse(_moneyController.text) ?? 0.0;
    }
    
    final orderQty = _isCrypto ? _quantityValue : (_quantityValue * _lotSize);
    final isDerivative = widget.instrumentType == 'OPTION' || widget.instrumentType == 'FUTURE';
    final marginPct = isDerivative ? 0.15 : 1.0;
    
    final existingQty = _existingHolding != null 
        ? (_existingHolding!['quantity'] as num).toDouble() 
        : 0.0;
        
    if (existingQty != 0.0) {
      if (existingQty > 0 && !widget.isBuy) {
        final netQty = existingQty - orderQty;
        if (netQty >= 0) {
          return 0.0;
        } else {
          final shortQty = netQty.abs();
          return shortQty * _price * marginPct;
        }
      }
      if (existingQty < 0 && widget.isBuy) {
        final netQty = existingQty + orderQty;
        if (netQty <= 0) {
          return 0.0;
        } else {
          final longQty = netQty;
          return longQty * _price * marginPct;
        }
      }
    }
    
    return orderQty * _price * marginPct;
  }

  Future<void> _submitOrder() async {
    if (_quantityValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_inputByMoney && _isCrypto
          ? 'Please enter an amount to invest.'
          : 'Please enter a valid quantity.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthService>();
      final order = await SupabaseService().placeOrder(
        symbol: widget.quote.symbol,
        market: widget.quote.market,
        side: widget.isBuy ? 'buy' : 'sell',
        quantity: _isCrypto ? _quantityValue : (_quantityValue * _lotSize),
        price: _price,
        isMarket: _isMarket,
        instrumentType: widget.instrumentType,
        strikePrice: widget.strikePrice,
        optionType: widget.optionType,
        expiryDate: widget.expiryDate,
        isExitOrder: widget.isExitOrder,
      );

      await authProvider.refreshUser(); // Update wallet balance

      // Funnel: record the user's first-ever trade (fires once per install).
      await AnalyticsService.logFirstTradeOnce(widget.quote.market);

      // Trigger push notification based on execution status
      if (order.isExecuted) {
        NotificationService().showNotification(
          id: order.id.hashCode,
          title: 'Order Executed',
          body: 'Your ${order.side} order for ${order.quantity} ${order.symbol} at ₹${order.price.toStringAsFixed(2)} has been executed.',
          category: NotificationCategory.orderExecuted,
        );
      } else if (order.isPending) {
        NotificationService().showNotification(
          id: order.id.hashCode,
          title: 'Order Placed (Pending)',
          body: '${order.side.toUpperCase()} ${order.quantity} ${order.symbol} placed at ₹${order.price.toStringAsFixed(2)}',
          category: NotificationCategory.orderPending,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully placed ${widget.isBuy ? 'BUY' : 'SELL'} order for ${widget.quote.symbol}!'),
          backgroundColor: AppColors.bull,
        ),
      );
      Navigator.pop(context); // Close screen
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to place order: $e'),
          backgroundColor: AppColors.bear,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// A beginner helper shown above the quantity inputs: tappable chips that
  /// open a plain-English definition for the terms relevant to this order type.
  Widget _buildTermHelp() {
    List<String> terms;
    if (widget.instrumentType == 'OPTION') {
      terms = ['Strike Price', 'Premium', 'Lot', 'Margin', 'Expiry'];
    } else if (widget.instrumentType == 'FUTURE') {
      terms = ['Lot', 'Margin', 'Expiry', 'LTP'];
    } else {
      terms = ['LTP', 'Market Order', 'Limit Order', 'Intraday'];
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.birch),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, size: 14, color: AppColors.goldDeep),
              const SizedBox(width: 6),
              Text(
                'New here? Tap a term to learn',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: terms.map((t) {
              return GestureDetector(
                onTap: () => showTermSheet(context, t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.birch),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.help_outline_rounded,
                          size: 13, color: AppColors.ink4),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTab(String title, bool isSelected, VoidCallback onTap, {bool isExpanded = false}) {
    Widget tab = GestureDetector(
      onTap: onTap,
      child: Container(
        width: isExpanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? (widget.isBuy ? AppColors.blue : AppColors.bear) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppColors.birch,
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.white : AppColors.ink4,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
    
    if (isExpanded) {
      return Expanded(child: tab);
    }
    return tab;
  }

  Widget _buildValidityOption(String title) {
    bool isSelected = _validity == title;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _validity = title),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.pureWhite : AppColors.warmWhite,
            border: Border.all(
              color: isSelected ? (widget.isBuy ? AppColors.blue : AppColors.bear) : AppColors.birch,
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: isSelected ? (widget.isBuy ? AppColors.blue : AppColors.bear) : AppColors.ink3,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, double> get _chargesPreview {
    final qty = _isCrypto ? _quantityValue : (_quantityValue * _lotSize);
    if (qty <= 0) {
      return {
        'brokerage': 0, 'stamp_duty': 0, 'stt': 0,
        'exchange_charges': 0, 'gst': 0, 'tax_charges': 0, 'total_charges': 0
      };
    }
    return SupabaseService().calculateTransactionCharges(
      instrumentType: widget.instrumentType,
      side: widget.isBuy ? 'buy' : 'sell',
      quantity: qty,
      price: _price,
      isIntraday: _isIntraday,
    );
  }

  Widget _buildChargeBreakdownPanel(Color color) {
    final charges = _chargesPreview;
    final qty = _isCrypto ? _quantityValue : (_quantityValue * _lotSize);
    final price = _price;
    final totalValue = qty * price;
    final totalCharges = charges['total_charges'] ?? 0.0;

    final brokerage = charges['brokerage'] ?? 0.0;
    final stampDuty = charges['stamp_duty'] ?? 0.0;
    final stt = charges['stt'] ?? 0.0;
    final exchangeCharges = charges['exchange_charges'] ?? 0.0;
    final gst = charges['gst'] ?? 0.0;

    if (qty <= 0) return const SizedBox.shrink();

    final isDeriv = widget.instrumentType == 'FUTURE' || widget.instrumentType == 'OPTION';
    final marginUsed = widget.marginUsed ?? 0.0;
    
    double grandTotal = totalValue + (widget.isBuy ? totalCharges : 0);
    double estimatedPnl = 0.0;

    if (widget.isExitOrder) {
      if (_existingHolding != null) {
        final avgPrice = (_existingHolding!['avg_price'] ?? _existingHolding!['avg_entry_price'] as num?)?.toDouble() ?? 0.0;
        if (avgPrice > 0) {
          final sideSign = widget.isBuy ? -1 : 1;
          estimatedPnl = (price - avgPrice) * qty * sideSign;
        }
      }
      if (isDeriv) {
        if (marginUsed > 0) {
          grandTotal = marginUsed + estimatedPnl - totalCharges;
        } else {
          grandTotal = totalValue - totalCharges; // Long option close (receive premium value)
        }
      } else {
        grandTotal = totalValue - totalCharges;
      }
    } else if (isDeriv && !widget.isExitOrder) {
      final isOptionBuy = widget.instrumentType == 'OPTION' && widget.isBuy;
      final marginRequired = isOptionBuy ? totalValue : (totalValue * 0.15);
      grandTotal = marginRequired + totalCharges;
    } else if (!widget.isExitOrder && !widget.isBuy && _marginRequired > 0) {
      // Equity/crypto short: margin is blocked (money out), not proceeds received.
      grandTotal = _marginRequired + totalCharges;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                'ORDER SUMMARY',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'VIRTUAL MONEY',
                  style: GoogleFonts.inter(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFE65100),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildBillRow(
            '${_isCrypto ? _quantityValue.toStringAsFixed(6) : qty.toStringAsFixed(0)} ${widget.quote.symbol} × ₹${price.toStringAsFixed(2)}',
            '₹${totalValue.toStringAsFixed(2)}',
            AppColors.ink,
            isMain: true,
          ),
          if (isDeriv) ...[
            const SizedBox(height: 4),
            _buildBillRow(
              'Contract / Notional Value',
              '₹${totalValue.toStringAsFixed(2)}',
              AppColors.ink3,
            ),
          ],
          if (widget.isExitOrder) ...[
            if (marginUsed > 0) ...[
              const SizedBox(height: 4),
              _buildBillRow(
                'Margin to Release (~15%)',
                '₹${marginUsed.toStringAsFixed(2)}',
                AppColors.ink3,
              ),
            ] else ...[
              const SizedBox(height: 4),
              _buildBillRow(
                isDeriv ? 'Est. Premium Value to Receive' : 'Est. Holding Value to Receive',
                '₹${totalValue.toStringAsFixed(2)}',
                AppColors.ink3,
              ),
            ],
            const SizedBox(height: 4),
            _buildBillRow(
              'Est. P&L (LTP vs Entry)',
              '${estimatedPnl >= 0 ? "+" : "-"} ₹${estimatedPnl.abs().toStringAsFixed(2)}',
              estimatedPnl >= 0 ? AppColors.bull : AppColors.bear,
            ),
          ] else ...[
            if (isDeriv && (widget.instrumentType == 'FUTURE' || !widget.isBuy)) ...[
              const SizedBox(height: 4),
              _buildBillRow(
                'Initial Margin Required (15%)',
                '₹${(totalValue * 0.15).toStringAsFixed(2)}',
                AppColors.ink3,
              ),
            ],
            if (!isDeriv && !widget.isBuy && _marginRequired > 0) ...[
              const SizedBox(height: 4),
              _buildBillRow(
                'Margin Required (100%)',
                '₹${_marginRequired.toStringAsFixed(2)}',
                AppColors.ink3,
              ),
            ],
          ],
          const SizedBox(height: 6),
          Container(height: 0.5, color: AppColors.birch),
          const SizedBox(height: 6),
          _buildBillRow('Brokerage', '+ ₹${brokerage.toStringAsFixed(2)}', AppColors.ink3),
          if (stampDuty > 0) ...[
            const SizedBox(height: 4),
            _buildBillRow('Stamp Duty', '+ ₹${stampDuty.toStringAsFixed(2)}', AppColors.ink3),
          ],
          if (stt > 0) ...[
            const SizedBox(height: 4),
            _buildBillRow('STT', '+ ₹${stt.toStringAsFixed(2)}', AppColors.ink3),
          ],
          if (exchangeCharges > 0) ...[
            const SizedBox(height: 4),
            _buildBillRow('Exchange Charges', '+ ₹${exchangeCharges.toStringAsFixed(2)}', AppColors.ink3),
          ],
          if (gst > 0) ...[
            const SizedBox(height: 4),
            _buildBillRow('GST (18%)', '+ ₹${gst.toStringAsFixed(2)}', AppColors.ink3),
          ],
          const SizedBox(height: 8),
          Container(height: 1.5, color: color.withValues(alpha: 0.25)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.isExitOrder 
                    ? (grandTotal >= 0 ? 'You Receive (approx.)' : 'Total Payable')
                    : ((!widget.isBuy && !isDeriv && _marginRequired <= 0) ? 'You Receive (approx.)' : 'Total Payable'),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '₹${grandTotal.abs().toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: widget.isExitOrder
                      ? (estimatedPnl >= 0 ? AppColors.bull : AppColors.bear)
                      : (grandTotal >= 0 ? AppColors.bull : AppColors.bear),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Charges: ₹${totalCharges.toStringAsFixed(2)} • Deducted from virtual cash only',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: AppColors.ink5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillRow(String label, String value, Color valueColor, {bool isMain = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isMain ? 12 : 11,
              fontWeight: isMain ? FontWeight.w600 : FontWeight.w500,
              color: isMain ? AppColors.ink2 : AppColors.ink4,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isMain ? 12 : 11,
            fontWeight: isMain ? FontWeight.w700 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthService>();
    final walletBalance = authProvider.user?.walletBalance ?? 0.0;
    final color = widget.isBuy ? AppColors.blue : AppColors.bear;

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.pureWhite,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.quote.symbol,
              style: GoogleFonts.inter(
                color: AppColors.ink,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (widget.instrumentType == 'OPTION')
              Text(
                '${widget.optionType} | Strike: ₹${widget.strikePrice?.toStringAsFixed(0)} | Exp: ${widget.expiryDate}',
                style: GoogleFonts.inter(
                  color: AppColors.ink4,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: AppColors.ink4),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            color: AppColors.parchment,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_isCrypto ? "CRYPTO" : "NSE"}  ${AppFormat.formatINR(widget.quote.price)}',
                  style: GoogleFonts.inter(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // MAIN CARD
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Type toggle — hidden for exit orders
                      if (!_isCrypto && !widget.isExitOrder) ...[
                        Row(
                          children: [
                            _buildToggleTab(
                              widget.instrumentType == 'OPTION' ? 'MIS' : 'Intraday',
                              _isIntraday,
                              () => setState(() => _isIntraday = true),
                              isExpanded: true,
                            ),
                            const SizedBox(width: 12),
                            _buildToggleTab(
                              widget.instrumentType == 'OPTION' ? 'NRML' : 'Longterm',
                              !_isIntraday,
                              () => setState(() => _isIntraday = false),
                              isExpanded: true,
                            ),
                          ],
                        ),
                        // Product type description for options
                        if (widget.instrumentType == 'OPTION') ...[
                          const SizedBox(height: 8),
                          Text(
                            _isIntraday
                                ? 'MIS — Auto-squared off at 3:20 PM. Lower margin.'
                                : 'NRML — Carry forward until expiry. Full margin.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.ink4,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                      // Exit order banner (replaces the product type tabs)
                      if (widget.isExitOrder && !_isCrypto) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.bear.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.bear.withValues(alpha: 0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.exit_to_app_rounded, size: 14, color: AppColors.bear),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Closing existing position — no additional margin required',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.bear,
                                    ),
                                  ),
                                ],
                              ),
                               // 15% margin disclaimer for F&O
                              if (widget.marginUsed != null &&
                                  (widget.instrumentType == 'FUTURE' || widget.instrumentType == 'OPTION')) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Your margin blocked: ₹${widget.marginUsed!.toStringAsFixed(0)} (~15% of notional). P&L is calculated on the full notional position value. Since you bought only at 15% margin, exiting is also capped/calculated at 15% margin.',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AppColors.ink3,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Quantity section
                      _buildTermHelp(),
                      if (_isCrypto) ...[
                        // Mode toggle: Qty vs Amount
                        Row(
                          children: [
                            _buildToggleTab('Quantity', !_inputByMoney, () => setState(() => _inputByMoney = false), isExpanded: true),
                            const SizedBox(width: 12),
                            _buildToggleTab('Amount (₹)', _inputByMoney, () => setState(() => _inputByMoney = true), isExpanded: true),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_inputByMoney) ...[
                          // Money input
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Amount to invest', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _moneyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  prefixText: '₹ ',
                                  prefixStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.ink3),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'You will get ≈ ${_quantityValue.toStringAsFixed(8)} ${widget.quote.symbol}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink4),
                              ),
                            ],
                          ),
                        ] else ...[
                          // Decimal quantity input for crypto
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Quantity', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _qtyController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Price', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                                        GestureDetector(
                                          onTap: () => setState(() => _isMarket = !_isMarket),
                                          child: Text(_isMarket ? 'Limit' : 'Market', style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _priceController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      enabled: !_isMarket,
                                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500, color: _isMarket ? AppColors.ink5 : AppColors.ink),
                                      decoration: InputDecoration(
                                        hintText: _isMarket ? widget.quote.price.toStringAsFixed(2) : '0.00',
                                        filled: _isMarket,
                                        fillColor: AppColors.parchment,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                                        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ] else ...[
                        // Original stock/option quantity+price row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isDerivative
                                        ? 'Qty (Lots)'
                                        : 'Quantity',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.ink3,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_isDerivative)
                                    Text(
                                      '1 Lot = $_lotSize qty',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: AppColors.ink5,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _qtyController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Price
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Price', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                                      GestureDetector(
                                        onTap: () => setState(() => _isMarket = !_isMarket),
                                        child: Text(_isMarket ? 'Limit' : 'Market', style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _priceController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    enabled: !_isMarket,
                                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w500, color: _isMarket ? AppColors.ink5 : AppColors.ink),
                                    decoration: InputDecoration(
                                      hintText: _isMarket ? widget.quote.price.toStringAsFixed(2) : '0.00',
                                      filled: _isMarket,
                                      fillColor: AppColors.parchment,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                                      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Toggles (hide for crypto)
                if (!_isCrypto)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.sm,
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Row(
                            children: [
                              Text('Stoploss', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(width: 4),
                              Icon(Icons.info_outline, size: 16, color: color),
                            ],
                          ),
                          value: _isStoploss,
                          activeThumbColor: color,
                          activeTrackColor: color.withValues(alpha: 0.5),
                          onChanged: (val) => setState(() => _isStoploss = val),
                        ),
                        if (_isStoploss)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                            child: TextField(
                              controller: _triggerPriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Trigger Price',
                                labelStyle: TextStyle(color: AppColors.ink4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                              ),
                            ),
                          ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: Row(
                            children: [
                              Text('Market protection', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(width: 4),
                              Icon(Icons.info_outline, size: 16, color: color),
                            ],
                          ),
                          value: _isMarketProtection,
                          activeThumbColor: color,
                          activeTrackColor: color.withValues(alpha: 0.5),
                          onChanged: (val) => setState(() => _isMarketProtection = val),
                        ),
                      ],
                    ),
                  ),

                // Advanced Toggle (hide for crypto)
                if (!_isCrypto) ...[
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => setState(() => _isAdvancedOpen = !_isAdvancedOpen),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Advanced',
                          style: GoogleFonts.inter(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          _isAdvancedOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: color,
                        ),
                      ],
                    ),
                  ),

                  if (_isAdvancedOpen) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.pureWhite,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: AppShadows.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Validity', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildValidityOption('DAY'),
                              const SizedBox(width: 8),
                              _buildValidityOption('IOC'),
                              const SizedBox(width: 8),
                              _buildValidityOption('Minutes'),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Disclosed Qty.', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _disclosedQtyController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Minutes', style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    TextField(
                                      enabled: _validity == 'Minutes',
                                      decoration: InputDecoration(
                                        hintText: '1 minute',
                                        filled: _validity != 'Minutes',
                                        fillColor: AppColors.parchment,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.birch)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 80), // Padding for footer
              ],
            ),
          ),
          
          // FOOTER
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Live charges breakdown — shown when quantity > 0
                  if (_quantityValue > 0)
                    _buildChargeBreakdownPanel(color),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(_inputByMoney && _isCrypto ? 'Amount ' : 'Margin ', style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                            Flexible(
                              child: Text(AppFormat.formatINR(_marginRequired), style: GoogleFonts.inter(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            Text(' • ', style: GoogleFonts.inter(color: AppColors.ink4)),
                            Text('Avail. ', style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                            Flexible(
                              child: Text(AppFormat.formatINR(walletBalance), style: GoogleFonts.inter(color: _marginRequired > walletBalance ? AppColors.bear : color, fontSize: 12, fontWeight: _marginRequired > walletBalance ? FontWeight.bold : FontWeight.normal)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.birch),
                        ),
                        child: Icon(Icons.show_chart, size: 16, color: AppColors.ink),
                      )
                    ],
                  ),
                  if (_inputByMoney && _isCrypto && _quantityValue > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 14, color: AppColors.ink4),
                        const SizedBox(width: 4),
                        Text(
                          'You will receive ≈ ${_quantityValue.toStringAsFixed(8)} ${widget.quote.symbol}',
                          style: GoogleFonts.inter(color: AppColors.ink3, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Show insufficient balance warning + top up button
                  if (_marginRequired > walletBalance && _quantityValue > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bear.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.bear.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, color: AppColors.bear, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Insufficient Balance',
                                  style: GoogleFonts.inter(
                                    color: AppColors.bear,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'You need ${AppFormat.formatINR(_marginRequired - walletBalance)} more to place this order.',
                                  style: GoogleFonts.inter(
                                    color: AppColors.ink3,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              // Navigate to wallet screen
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const WalletScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.bull,
                              foregroundColor: AppColors.pureWhite,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: Text(
                              'TOP UP',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    SwipeButton(
                      text: widget.isBuy ? 'SWIPE TO BUY' : 'SWIPE TO SELL',
                      color: color,
                      isLoading: _isLoading,
                      onSwipeComplete: _submitOrder,
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
