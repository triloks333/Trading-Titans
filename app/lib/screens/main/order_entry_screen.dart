import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/money.dart';
import '../../models/quote.dart';
import '../../services/auth_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/auth_kit.dart';
import '../../services/supabase_service.dart';
import '../../services/analytics_service.dart';
import '../../services/fo_instruments_service.dart';
import '../../services/churn_telemetry_service.dart';
import '../../services/action_reaction_engine.dart';
import '../../widgets/swipe_button.dart';
import '../../widgets/info_tooltip.dart';
import 'subscribe_screen.dart';

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
  /// Buy or sell. Starts from how the ticket was opened; the toggle switches it
  /// (except on an exit, which closes a known side).
  late bool _isBuy = widget.isBuy;
  bool _showSummary = false;
  final _atMarket = TextEditingController(), _minutes = TextEditingController();

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

  String get _exchangeLabel {
    switch (widget.quote.market) {
      case 'crypto':
        return 'CRYPTO';
      case 'pakistan_stock':
        return 'PSX';
      case 'italy_stock':
        return 'BORSA ITALIANA';
      case 'us_stock':
        return 'US';
      case 'stock':
      default:
        return 'NSE';
    }
  }

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

    _priceController.text =
        Money.bare(widget.quote.price, from: Money.sourceFor(widget.quote.market));
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
    _atMarket.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _updateState() {
    setState(() {});
  }

  double get _quantityValue {
    if (_inputByMoney && _isCrypto) {
      // The amount is typed in the user's display currency, but _price is in the
      // instrument's own currency. Convert before dividing, or a dollar-entered
      // amount would buy ~88x too much.
      final money = Money.fromDisplay(
        double.tryParse(_moneyController.text) ?? 0.0,
        market: widget.quote.market,
      );
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

  /// Price in the instrument's own currency — the only currency the order engine
  /// understands.
  double get _price {
    if (_isMarket) return widget.quote.price;
    final typed = double.tryParse(_priceController.text);
    if (typed == null) return widget.quote.price;
    // A limit price is typed in the display currency, so convert it back.
    return Money.fromDisplay(typed, market: widget.quote.market);
  }

  double get _marginRequired {
    // Exit orders (closing existing positions) never require new capital
    if (widget.isExitOrder) return 0.0;

    if (_inputByMoney && _isCrypto) {
      // Compared against the wallet, which is rupees, so the typed figure has to
      // come back to rupees regardless of what is being displayed.
      return Money.typedToInr(double.tryParse(_moneyController.text) ?? 0.0);
    }

    final orderQty = _isCrypto ? _quantityValue : (_quantityValue * _lotSize);
    final isMarginDerivative = widget.instrumentType == 'FUTURE' || (widget.instrumentType == 'OPTION' && !_isBuy);
    final marginPct = isMarginDerivative ? 0.15 : 1.0;
    
    final existingQty = _existingHolding != null 
        ? (_existingHolding!['quantity'] as num).toDouble() 
        : 0.0;
        
    if (existingQty != 0.0) {
      if (existingQty > 0 && !_isBuy) {
        final netQty = existingQty - orderQty;
        if (netQty >= 0) {
          return 0.0;
        } else {
          final shortQty = netQty.abs();
          return shortQty * _price * marginPct;
        }
      }
      if (existingQty < 0 && _isBuy) {
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

  bool get _isContractExpired {
    if (widget.expiryDate == null || widget.expiryDate!.isEmpty) return false;
    final exp = DateTime.tryParse(widget.expiryDate!);
    if (exp == null) return false;
    final cutoff = DateTime(exp.year, exp.month, exp.day, 15, 30);
    return DateTime.now().isAfter(cutoff);
  }

  Future<void> _submitOrder() async {
    if (_isContractExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This contract has expired and cannot be traded.'),
          backgroundColor: AppColors.bear,
        ),
      );
      return;
    }

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
        side: _isBuy ? 'buy' : 'sell',
        quantity: _isCrypto ? _quantityValue : (_quantityValue * _lotSize),
        price: _price,
        isMarket: _isMarket,
        instrumentType: widget.instrumentType,
        strikePrice: widget.strikePrice,
        optionType: widget.optionType,
        expiryDate: widget.expiryDate,
        isExitOrder: widget.isExitOrder,
      );

      ChurnTelemetryService.instance.recordTradePlaced(
          symbol: widget.quote.symbol, side: _isBuy ? 'buy' : 'sell',
          qty: _isCrypto ? _quantityValue : (_quantityValue * _lotSize), segment: widget.instrumentType);
      await authProvider.refreshUser(); // Update wallet balance

      // Funnel: record the user's first-ever trade (fires once per install).
      await AnalyticsService.logFirstTradeOnce(widget.quote.market);

      // Deliberately no local notification here. Every row written to
      // `notifications` fires trg_push_on_notification -> push-notification ->
      // FCM, and the server already writes exactly one row per event ("Order
      // Pending" from place-order, "<Side> Order Executed" from the
      // notify_order_executed trigger). Posting a local one on top is what put
      // two of every alert in the tray. The server path also covers what this
      // one never could: a pending order filling later, or the app being closed.

      // Fire-and-forget: a filled order can complete First Blood, Sniper,
      // Morning Bell and friends, so re-check straight away for instant
      // feedback. Failures are logged inside the service and never block the
      // order flow; the nightly sweep would catch it anyway.
      SupabaseService().evaluateChallenges();

      if (!mounted) return;
      final side = _isBuy ? 'BUY' : 'SELL';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // The removed local push was the instant signal for whether the order
          // filled or is still resting; the server push carries that a second or
          // two later, so say it here rather than losing the immediacy. Any
          // non-executed status keeps the original wording, which is accurate
          // for a resting order.
          content: Text(order.isExecuted
              ? '$side order for ${widget.quote.symbol} executed!'
              : 'Successfully placed $side order for ${widget.quote.symbol}!'),
          backgroundColor: AppColors.bull,
        ),
      );
      Navigator.pop(context); // Close screen
    } catch (e) {
      if (!mounted) return;
      final errText = e.toString().replaceFirst(RegExp(r'^(Exception|_Exception):\s*'), '');
      final isInsufficient = errText.toLowerCase().contains('insufficient');
      var offerTopUp = false;
      if (isInsufficient) {
        final available = context.read<AuthService>().user?.walletBalance ?? 0.0;
        ChurnTelemetryService.instance.recordMarginShortfall(
          symbol: widget.quote.symbol,
          requiredMargin: _marginRequired,
          availableCash: available,
        );
        // No top-up pitch right after a revenge re-entry or under ₹1,000 left.
        offerTopUp = await ActionReactionEngine.instance
            .offerMarginTopUp(symbol: widget.quote.symbol, required: _marginRequired, available: available);
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isInsufficient ? errText : 'Failed to place order: $errText'),
          backgroundColor: AppColors.bear,
          action: offerTopUp
              ? SnackBarAction(
                  label: 'TOP UP',
                  textColor: Colors.white,
                  onPressed: () async {
                    ChurnTelemetryService.instance.recordButtonTap('order_ticket_insufficient_cash_topup_cta');
                    final auth = context.read<AuthService>();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SubscribeScreen(initialTabIndex: 1),
                      ),
                    );
                    if (mounted) await auth.refreshUser();
                  },
                )
              : null,
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
                style: GoogleFonts.ibmPlexSans(
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
                        style: GoogleFonts.ibmPlexSans(
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

  /// Side colour for the whole ticket: green to buy, red to sell.
  Color get _sideColor => _isBuy ? AppColors.bull : AppColors.bear;
  Color get _onSide => _isBuy && AppColors.isDark ? const Color(0xFF04140B) : Colors.white;

  /// The design's chip: accent-tinted when selected, outlined otherwise.
  Widget _chip(String title, bool isSelected, VoidCallback? onTap) => Expanded(
        child: Material(
          color: isSelected ? AppColors.goldPale : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: BorderSide(color: isSelected ? AppColors.goldMid : AppColors.birch),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppFonts.sans(size: 13, weight: FontWeight.w500, color: isSelected ? AppColors.goldMid : AppColors.ink3)),
            ),
          ),
        ),
      );

  Widget _chipRow(List<Widget> chips) => Row(children: [
        for (var i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: 6), chips[i]],
      ]);

  /// Market, Limit, SL, SL-M map onto the two flags the order engine reads.
  String get _orderType => _isStoploss ? (_isMarket ? 'SL-M' : 'SL') : (_isMarket ? 'Market' : 'Limit');
  void _setOrderType(String t) => setState(() {
        _isMarket = t == 'Market' || t == 'SL-M';
        _isStoploss = t == 'SL' || t == 'SL-M';
      });

  Widget _buildValidityOption(String title) =>
      _chip(title == 'DAY' ? 'Day' : title, _validity == title, () => setState(() => _validity = title));

  Map<String, double> get _chargesPreview {
    final qty = _isCrypto ? _quantityValue : (_quantityValue * _lotSize);
    if (qty <= 0 || widget.quote.market != 'stock') {
      return {
        'brokerage': 0, 'stamp_duty': 0, 'stt': 0,
        'exchange_charges': 0, 'gst': 0, 'tax_charges': 0, 'total_charges': 0
      };
    }
    return SupabaseService().calculateTransactionCharges(
      instrumentType: widget.instrumentType,
      side: _isBuy ? 'buy' : 'sell',
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

    if (qty <= 0) return const SizedBox.shrink();

    final isDeriv = widget.instrumentType == 'FUTURE' || widget.instrumentType == 'OPTION';
    final marginUsed = widget.marginUsed ?? 0.0;
    
    double grandTotal = totalValue + (_isBuy ? totalCharges : 0);
    double estimatedPnl = 0.0;

    if (widget.isExitOrder) {
      if (_existingHolding != null) {
        final avgPrice = (_existingHolding!['avg_price'] ?? _existingHolding!['avg_entry_price'] as num?)?.toDouble() ?? 0.0;
        if (avgPrice > 0) {
          final sideSign = _isBuy ? -1 : 1;
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
      final isOptionBuy = widget.instrumentType == 'OPTION' && _isBuy;
      final marginRequired = isOptionBuy ? totalValue : (totalValue * 0.15);
      grandTotal = marginRequired + totalCharges;
    } else if (!widget.isExitOrder && !_isBuy && _marginRequired > 0) {
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
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.titanGoldSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'VIRTUAL MONEY',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.titanGold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildBillRow(
            '${_isCrypto ? _quantityValue.toStringAsFixed(6) : qty.toStringAsFixed(0)} ${widget.quote.symbol} × ${Money.instrument(price, market: widget.quote.market)}',
            Money.instrument(totalValue, market: widget.quote.market),
            AppColors.ink,
            isMain: true,
          ),
          if (widget.isExitOrder) ...[
            if (marginUsed > 0) ...[
              const SizedBox(height: 4),
              _buildBillRow(
                'Margin to Release (~15%)',
                Money.wallet(marginUsed, decimals: 2),
                AppColors.ink3,
              ),
            ] else ...[
              const SizedBox(height: 4),
              _buildBillRow(
                isDeriv ? 'Est. Premium Value to Receive' : 'Est. Holding Value to Receive',
                Money.instrument(totalValue, market: widget.quote.market),
                AppColors.ink3,
              ),
            ],
            const SizedBox(height: 4),
            _buildBillRow(
              'Est. P&L (LTP vs Entry)',
              '${estimatedPnl >= 0 ? "+" : "-"} ${Money.wallet(estimatedPnl.abs(), decimals: 2)}',
              estimatedPnl >= 0 ? AppColors.bull : AppColors.bear,
            ),
          ] else ...[
            if (isDeriv && (widget.instrumentType == 'FUTURE' || !_isBuy)) ...[
              const SizedBox(height: 4),
              _buildBillRow(
                'Initial Margin Required (15%)',
                Money.instrument(totalValue * 0.15, market: widget.quote.market),
                AppColors.ink3,
              ),
            ],
            if (!isDeriv && !_isBuy && _marginRequired > 0) ...[
              const SizedBox(height: 4),
              _buildBillRow(
                'Margin Required (100%)',
                Money.instrument(_marginRequired, market: widget.quote.market),
                AppColors.ink3,
              ),
            ],
          ],
          const SizedBox(height: 6),
          Container(height: 0.5, color: AppColors.birch),
          const SizedBox(height: 6),
          _buildBillRow('Charges & taxes', '+ ${Money.instrument(totalCharges, market: widget.quote.market)}', AppColors.ink3),
          const SizedBox(height: 8),
          Container(height: 1.5, color: color.withValues(alpha: 0.25)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.isExitOrder 
                    ? (grandTotal >= 0 ? 'You Receive (approx.)' : 'Total Payable')
                    : ((!_isBuy && !isDeriv && _marginRequired <= 0) ? 'You Receive (approx.)' : 'Total Payable'),
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text(
                Money.instrument(grandTotal.abs(), market: widget.quote.market),
                style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.isExitOrder
                      ? (estimatedPnl >= 0 ? AppColors.bull : AppColors.bear)
                      : (grandTotal >= 0 ? AppColors.bull : AppColors.bear),
                ),
              ),
            ],
          ),
          // The wallet is always in rupees. Whenever the figure above is not
          // rupees - because the user views dollars, or the stock is US-priced,
          // or both - state the real charge before they swipe to confirm.
          if (Money.differsFromWallet(widget.quote.market)) ...[
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final inrValue = Money.inrValueOf(
                  grandTotal.abs(),
                  market: widget.quote.market,
                );
                final note = Money.conversionNote(market: widget.quote.market);
                return Text(
                  note == null
                      ? '\u2248 ${Money.walletChargeInr(inrValue)} moves in your wallet'
                      : '\u2248 ${Money.walletChargeInr(inrValue)} moves in your wallet $note',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Text(
            widget.quote.market != 'stock'
                ? 'No brokerage or Indian taxes on non-domestic trades • Virtual cash only'
                : 'Charges: ${Money.instrument(totalCharges, market: widget.quote.market)} • Deducted from virtual cash only',
            style: GoogleFonts.ibmPlexSans(
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
            style: GoogleFonts.ibmPlexSans(
              fontSize: isMain ? 12 : 11,
              fontWeight: isMain ? FontWeight.w600 : FontWeight.w500,
              color: isMain ? AppColors.ink2 : AppColors.ink4,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.ibmPlexMono(fontFeatures: const [FontFeature.tabularFigures()], 
            fontSize: isMain ? 12 : 11,
            fontWeight: isMain ? FontWeight.w700 : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  /// Label above a field, as in the design.
  Widget _label(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: AppFonts.sans(size: 12, weight: FontWeight.w500, color: AppColors.ink3)));

  /// 48 dp mono field with an optional trailing stepper or prefix.
  Widget _field(TextEditingController c,
      {bool enabled = true,
      String? hint,
      String? prefix,
      bool decimal = true,
      VoidCallback? onStep,
      String stepLabel = 'Increase',
      List<TextInputFormatter>? formatters}) =>
      Container(
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? AppColors.pureWhite : AppColors.cream,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.birch),
        ),
        child: Row(children: [
          if (prefix != null)
            Padding(padding: const EdgeInsets.only(left: 12), child: Text(prefix, style: AppFonts.mono(size: 16, color: AppColors.ink4))),
          Expanded(
            child: TextField(
              controller: c,
              enabled: enabled,
              keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
              inputFormatters: formatters,
              style: AppFonts.mono(size: 16, weight: FontWeight.w500, color: enabled ? AppColors.ink : AppColors.ink4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppFonts.mono(size: 16, color: AppColors.ink4),
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ),
          if (onStep != null)
            Semantics(
              button: true,
              label: stepLabel,
              excludeSemantics: true,
              child: InkWell(
                onTap: onStep,
                child: Container(
                  width: 44,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.birch))),
                  child: Icon(Icons.add_rounded, size: 20, color: AppColors.ink),
                ),
              ),
            ),
        ]),
      );

  /// Adds one unit (one lot for F&O, 0.01 for crypto, 1 share otherwise).
  void _stepQty() {
    if (_isCrypto) {
      final v = (double.tryParse(_qtyController.text) ?? 0) + 0.01;
      _qtyController.text = v.toStringAsFixed(v < 1 ? 4 : 2);
    } else {
      _qtyController.text = ((int.tryParse(_qtyController.text) ?? 0) + 1).toString();
    }
  }

  Widget _header() {
    final q = widget.quote;
    final up = q.change >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 10, AppSpacing.lg, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.birch))),
      child: Row(children: [
        AuthIconButton(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => Navigator.pop(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(q.symbol,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: AppCard.badge(AppColors.cream),
                child: Text(_exchangeLabel, style: AppText.badge.copyWith(color: AppColors.ink3)),
              ),
            ]),
            Text.rich(
              TextSpan(style: AppFonts.mono(size: 12, color: AppColors.ink3), children: [
                if (widget.instrumentType == 'OPTION')
                  TextSpan(text: '${widget.optionType} ${Money.wallet(widget.strikePrice ?? 0, decimals: 0)} · ${widget.expiryDate} · '),
                TextSpan(text: Money.instrument(q.price, market: q.market)),
                TextSpan(
                    text: ' ${up ? '▲' : '▼'}${q.changePct.abs().toStringAsFixed(2)}%',
                    style: TextStyle(color: up ? AppColors.bull : AppColors.bear)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        ListenableBuilder(
          listenable: ThemeService(),
          builder: (_, _) => AuthIconButton(
            icon: AppColors.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            label: 'Toggle light or dark theme',
            onTap: () => ThemeService().setThemeMode(AppColors.isDark ? ThemeMode.light : ThemeMode.dark),
          ),
        ),
      ]),
    );
  }

  /// Buy / Sell segmented control. Locked on an exit, which closes a known side.
  Widget _sideToggle() {
    Widget seg(String label, bool buy) {
      final on = _isBuy == buy;
      final bg = buy ? AppColors.bull : AppColors.bear;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: widget.isExitOrder ? null : () => setState(() => _isBuy = buy),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? bg : Colors.transparent, borderRadius: BorderRadius.circular(7)),
              child: Text(label,
                  style: AppFonts.sans(
                      size: 13,
                      weight: FontWeight.w600,
                      color: on ? (buy && AppColors.isDark ? const Color(0xFF04140B) : Colors.white) : AppColors.ink3)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(children: [seg('Buy', true), const SizedBox(width: 4), seg('Sell', false)]),
    );
  }

  Widget _exitBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bearLight,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.bear.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.exit_to_app_rounded, size: 14, color: AppColors.bear),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Closing existing position — no additional margin required',
                  style: AppFonts.sans(size: 11, weight: FontWeight.w600, color: AppColors.bear)),
            ),
          ]),
          if (widget.marginUsed != null && _isDerivative) ...[
            const SizedBox(height: 6),
            Text(
              'Your margin blocked: ${Money.wallet(widget.marginUsed!, decimals: 0)} (~15% of notional). P&L is calculated on the full notional position value. Since you bought only at 15% margin, exiting is also capped/calculated at 15% margin.',
              style: AppFonts.mono(size: 10, color: AppColors.ink3),
            ),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final walletBalance = context.watch<AuthService>().user?.walletBalance ?? 0.0;
    final color = _sideColor;
    final optionLabels = widget.instrumentType == 'OPTION';
    final moneyMode = _inputByMoney && _isCrypto;
    final marketHint = Money.bare(widget.quote.price, from: Money.sourceFor(widget.quote.market));

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 24),
              children: [
                _sideToggle(),
                const SizedBox(height: 16),
                if (widget.isExitOrder && !_isCrypto) ...[_exitBanner(), const SizedBox(height: 16)],
                // Product: hidden for crypto and exits, which have no product choice.
                if (!_isCrypto && !widget.isExitOrder) ...[
                  _chipRow([
                    _chip(optionLabels ? 'NRML' : 'Delivery', !_isIntraday, () => setState(() => _isIntraday = false)),
                    _chip(optionLabels ? 'MIS' : 'Intraday', _isIntraday, () => setState(() => _isIntraday = true)),
                  ]),
                  if (optionLabels) ...[
                    const SizedBox(height: 6),
                    Text(
                      _isIntraday ? 'MIS — Auto-squared off at 3:20 PM. Lower margin.' : 'NRML — Carry forward until expiry. Full margin.',
                      style: AppFonts.sans(size: 11, color: AppColors.ink4),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                Text('ORDER TYPE', style: AppText.sectionLabel),
                const SizedBox(height: 6),
                _chipRow([
                  for (final t in _isCrypto ? const ['Market', 'Limit'] : const ['Market', 'Limit', 'SL', 'SL-M'])
                    _chip(t, _orderType == t, () => _setOrderType(t)),
                ]),
                const SizedBox(height: 16),
                _buildTermHelp(),
                if (_isCrypto) ...[
                  _chipRow([
                    _chip('Quantity', !_inputByMoney, () => setState(() => _inputByMoney = false)),
                    _chip('Amount (${Money.symbol})', _inputByMoney, () => setState(() => _inputByMoney = true)),
                  ]),
                  const SizedBox(height: 16),
                ],
                if (moneyMode) ...[
                  _label('Amount to invest'),
                  _field(_moneyController, prefix: Money.symbol),
                  const SizedBox(height: 6),
                  Text('Fractional quantity is calculated from the amount: ≈ ${_quantityValue.toStringAsFixed(8)} ${widget.quote.symbol}',
                      style: AppFonts.sans(size: 11, color: AppColors.ink4)),
                ] else
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label(_isDerivative ? 'Qty (lots) · 1 lot = $_lotSize' : 'Quantity'),
                        _field(
                          _qtyController,
                          decimal: _isCrypto,
                          formatters: _isCrypto ? null : [FilteringTextInputFormatter.digitsOnly],
                          onStep: _stepQty,
                          stepLabel: 'Increase quantity',
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Price'),
                        _isMarket
                            ? _field(_atMarket, enabled: false, hint: 'At market')
                            : _field(_priceController, hint: marketHint),
                      ]),
                    ),
                  ]),
                if (_isStoploss) ...[
                  const SizedBox(height: 16),
                  _label('Stoploss trigger'),
                  _field(_triggerPriceController, hint: marketHint),
                ],
                if (!_isCrypto) ...[
                  const SizedBox(height: 16),
                  Text('VALIDITY', style: AppText.sectionLabel),
                  const SizedBox(height: 6),
                  _chipRow([_buildValidityOption('DAY'), _buildValidityOption('IOC'), _buildValidityOption('Minutes')]),
                  const SizedBox(height: 16),
                  _advanced(),
                ],
              ],
            ),
          ),
          _footer(walletBalance, color),
        ]),
      ),
    );
  }

  Widget _advanced() => Container(
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.birch),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => _isAdvancedOpen = !_isAdvancedOpen),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Text('Advanced · disclosed qty, market protection',
                      style: AppFonts.sans(size: 13, weight: FontWeight.w600, color: AppColors.ink)),
                ),
                Icon(_isAdvancedOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.ink4),
              ]),
            ),
          ),
          if (_isAdvancedOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Disclosed qty'),
                      _field(_disclosedQtyController, decimal: false),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Minutes'),
                      _field(_minutes, enabled: _validity == 'Minutes', hint: '1 minute', decimal: false),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Market protection', style: AppFonts.sans(size: 14, weight: FontWeight.w600, color: AppColors.ink)),
                  subtitle: Text('Caps how far a market order can fill from the last price.', style: AppText.bodySmall),
                  value: _isMarketProtection,
                  onChanged: (v) => setState(() => _isMarketProtection = v),
                ),
              ]),
            ),
        ]),
      );

  /// One-line "Required + charges · Avail." summary (tap for the full bill),
  /// then the expired notice, the top-up prompt, or the swipe to place.
  Widget _footer(double walletBalance, Color color) {
    final chargesNative = _chargesPreview['total_charges'] ?? 0.0;
    final marginRequiredInr = Money.inrValueOf(_marginRequired, market: widget.quote.market);
    final chargesInr = Money.inrValueOf(chargesNative, market: widget.quote.market);
    final totalRequiredInr = marginRequiredInr + (_marginRequired > 0 ? chargesInr : 0.0);
    final insufficient = totalRequiredInr > walletBalance && _quantityValue > 0 && !widget.isExitOrder;
    final requiredLabel =
        _inputByMoney && _isCrypto ? 'Amount' : ((widget.instrumentType == 'OPTION' && _isBuy) ? 'Total' : 'Required');
    TextSpan mono(String t, {Color? c}) => TextSpan(text: t, style: AppFonts.mono(size: 12, color: c ?? AppColors.ink));

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 12, AppSpacing.lg, 16),
      decoration: BoxDecoration(color: AppColors.pureWhite, border: Border(top: BorderSide(color: AppColors.birch))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_showSummary && _quantityValue > 0) _buildChargeBreakdownPanel(color),
        InkWell(
          onTap: _quantityValue > 0 ? () => setState(() => _showSummary = !_showSummary) : null,
          child: Row(children: [
            Expanded(
              child: Text.rich(TextSpan(style: AppFonts.sans(size: 12, color: AppColors.ink4), children: [
                TextSpan(text: '$requiredLabel '),
                mono(Money.instrument(_marginRequired, market: widget.quote.market)),
                const TextSpan(text: ' + charges '),
                mono(Money.instrument(chargesNative, market: widget.quote.market), c: AppColors.ink4),
              ])),
            ),
            Text.rich(TextSpan(style: AppFonts.sans(size: 12, color: AppColors.ink4), children: [
              const TextSpan(text: 'Avail. '),
              mono(Money.wallet(walletBalance), c: insufficient ? AppColors.bear : AppColors.ink),
            ])),
            if (_quantityValue > 0)
              Icon(_showSummary ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 18, color: AppColors.ink4),
          ]),
        ),
        const SizedBox(height: 10),
        if (_isContractExpired)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.bearLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.bear.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.error_outline_rounded, color: AppColors.bear, size: 18),
              const SizedBox(width: 8),
              Text('CONTRACT EXPIRED', style: AppFonts.sans(size: 13, weight: FontWeight.w700, color: AppColors.bear, spacing: 0.8)),
            ]),
          )
        else if (insufficient)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bearLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.bear.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(Icons.account_balance_wallet_outlined, color: AppColors.bear, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Insufficient balance', style: AppFonts.sans(size: 13, weight: FontWeight.w700, color: AppColors.bear)),
                  const SizedBox(height: 2),
                  Text('You need ${Money.wallet(totalRequiredInr - walletBalance)} more to place this order.',
                      style: AppFonts.mono(size: 11, color: AppColors.ink3)),
                ]),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final auth = context.read<AuthService>();
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscribeScreen(initialTabIndex: 1)));
                  if (mounted) await auth.refreshUser();
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: const Text('Top up'),
              ),
            ]),
          )
        else
          SwipeButton(
            text: _isBuy ? 'Swipe to buy' : 'Swipe to sell',
            color: color,
            textColor: _onSide,
            isLoading: _isLoading,
            onSwipeComplete: _submitOrder,
          ),
      ]),
    );
  }
}
