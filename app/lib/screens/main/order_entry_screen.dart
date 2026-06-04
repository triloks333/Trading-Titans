import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/quote.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/swipe_button.dart';
import '../../utils/lot_size.dart';

class OrderEntryScreen extends StatefulWidget {
  final Quote quote;
  final bool isBuy;
  final String instrumentType;
  final double? strikePrice;
  final String? optionType;
  final String? expiryDate;
  final double? prefilledQuantity;

  const OrderEntryScreen({
    super.key,
    required this.quote,
    required this.isBuy,
    this.instrumentType = 'EQUITY',
    this.strikePrice,
    this.optionType,
    this.expiryDate,
    this.prefilledQuantity,
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

  bool get _isCrypto => widget.quote.market == 'crypto';

  @override
  void initState() {
    super.initState();
    
    double initialQty = 1.0;
    if (widget.prefilledQuantity != null) {
      if (widget.instrumentType == 'OPTION' || widget.instrumentType == 'FUTURE') {
        final lotSize = getOptionLotSize(widget.quote.symbol);
        initialQty = widget.prefilledQuantity! / lotSize;
      } else {
        initialQty = widget.prefilledQuantity!;
      }
    }
    
    final qtyStr = _isCrypto 
        ? initialQty.toString() 
        : initialQty.toInt().toString();

    _qtyController = TextEditingController(text: qtyStr);
    _qtyController.addListener(_updateState);
    _priceController.addListener(_updateState);
    _moneyController.addListener(_updateState);
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
    if (widget.instrumentType == 'OPTION' || widget.instrumentType == 'FUTURE') {
      return getOptionLotSize(widget.quote.symbol);
    }
    return 1;
  }

  double get _price {
    if (_isMarket) return widget.quote.price;
    return double.tryParse(_priceController.text) ?? widget.quote.price;
  }

  double get _marginRequired {
    if (_inputByMoney && _isCrypto) {
      return double.tryParse(_moneyController.text) ?? 0.0;
    }
    return _quantityValue * _lotSize * _price;
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
      );

      await authProvider.refreshUser(); // Update wallet balance

      // Trigger push notification based on execution status
      if (order.isExecuted) {
        NotificationService().showNotification(
          id: order.id.hashCode,
          title: 'Order Executed',
          body: '${order.side.toUpperCase()} ${order.quantity} ${order.symbol} filled at ₹${order.price.toStringAsFixed(2)}',
        );
      } else if (order.isPending) {
        NotificationService().showNotification(
          id: order.id.hashCode,
          title: 'Order Placed (Pending)',
          body: '${order.side.toUpperCase()} ${order.quantity} ${order.symbol} placed at ₹${order.price.toStringAsFixed(2)}',
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
                      // Product Type (hide for crypto)
                      if (!_isCrypto) ...[
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
                      
                      // Quantity section
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
                                    widget.instrumentType == 'OPTION'
                                        ? 'Qty (Lots)'
                                        : 'Quantity',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.ink3,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (widget.instrumentType == 'OPTION')
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(_inputByMoney && _isCrypto ? 'Amount ' : 'Margin ', style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                          Text(AppFormat.formatINR(_marginRequired), style: GoogleFonts.inter(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(' • ', style: GoogleFonts.inter(color: AppColors.ink4)),
                          Text('Avail. ', style: GoogleFonts.inter(color: AppColors.ink4, fontSize: 12)),
                          Text(AppFormat.formatINR(walletBalance), style: GoogleFonts.inter(color: color, fontSize: 12)),
                        ],
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
                  const SizedBox(height: 16),
                  SwipeButton(
                    text: widget.isBuy ? 'SWIPE TO BUY' : 'SWIPE TO SELL',
                    color: color,
                    isLoading: _isLoading,
                    onSwipeComplete: _submitOrder,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
