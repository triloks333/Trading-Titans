class Order {
  final String id;
  final String symbol;
  final String name;
  final String market;
  final String side;
  final double quantity;
  final double price;
  final double total;
  final double realizedPnl;
  final String status;
  final DateTime? createdAt;
  final DateTime? executedAt;

  final String? orderType;
  final String? instrumentType;
  final double? strikePrice;
  final String? optionType;
  final String? expiryDate;
  final String? chargeConfigId;
  final double brokerage;
  final double stampDuty;
  final double taxCharges;
  final double totalCharges;

  /// Price in the instrument's own currency (USD for `us_stock`). Null for INR
  /// markets, where [price] is already native.
  ///
  /// [price] and [total] are always INR because that is what the wallet moved
  /// by; [nativePrice] is what the user actually saw and agreed to.
  final double? nativePrice;

  /// ISO code for [nativePrice], e.g. 'USD'. Null for INR markets.
  final String? nativeCurrency;

  /// USD to INR rate applied at fill. Kept so a past trade's rupee cost can be
  /// reconciled against its dollar price after the rate has moved.
  final double? fxRate;

  /// The trigger price the engine matches this order against. Null for a market
  /// order, which has no trigger.
  ///
  /// This exists because [price] is overloaded: it holds the limit while the
  /// order rests, then the engine overwrites it with the FILL price on
  /// execution. Only this column survives that overwrite, which makes it the
  /// single source of truth for "what did the user ask for".
  final double? limitPrice;

  Order({
    required this.id,
    required this.symbol,
    required this.name,
    required this.market,
    required this.side,
    required this.quantity,
    required this.price,
    required this.total,
    this.realizedPnl = 0.0,
    this.status = 'executed',
    this.createdAt,
    this.executedAt,
    this.orderType,
    this.instrumentType,
    this.strikePrice,
    this.optionType,
    this.expiryDate,
    this.chargeConfigId,
    this.brokerage = 0.0,
    this.stampDuty = 0.0,
    this.taxCharges = 0.0,
    this.totalCharges = 0.0,
    this.nativePrice,
    this.nativeCurrency,
    this.fxRate,
    this.limitPrice,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String? ?? json['_id'] as String? ?? json['order_id'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      market: json['market'] as String? ?? 'stock',
      side: json['side'] as String? ?? 'buy',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      realizedPnl: (json['realized_pnl'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'executed',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      executedAt: json['executed_at'] != null
          ? DateTime.tryParse(json['executed_at'] as String)
          : null,
      orderType: json['order_type'] as String?,
      instrumentType: json['instrument_type'] as String?,
      strikePrice: (json['strike_price'] as num?)?.toDouble(),
      optionType: json['option_type'] as String?,
      expiryDate: json['expiry_date'] as String?,
      chargeConfigId: json['charge_config_id'] as String?,
      brokerage: (json['brokerage'] as num?)?.toDouble() ?? 0.0,
      stampDuty: (json['stamp_duty'] as num?)?.toDouble() ?? 0.0,
      taxCharges: (json['tax_charges'] as num?)?.toDouble() ?? 0.0,
      totalCharges: (json['total_charges'] as num?)?.toDouble() ?? 0.0,
      nativePrice: (json['native_price'] as num?)?.toDouble(),
      nativeCurrency: json['native_currency'] as String?,
      fxRate: (json['fx_rate'] as num?)?.toDouble(),
      limitPrice: (json['limit_price'] as num?)?.toDouble(),
    );
  }

  bool get isBuy => side == 'buy';
  bool get isPending => status == 'pending';
  bool get isExecuted => status == 'executed';
  bool get isCancelled => status == 'cancelled';

  /// True when this order's own prices are in a currency other than INR.
  bool get isNativeCurrency => nativeCurrency != null && nativeCurrency != 'INR';

  /// Price to show the user, in the instrument's own currency.
  ///
  /// For a US order this is USD at both stages: while pending, [price] itself is
  /// still USD because the conversion only happens at fill; once executed,
  /// [price] holds the INR figure and [nativePrice] holds the USD one.
  double get displayPrice => nativePrice ?? price;

  /// The trigger to show on a limit order, in the instrument's own currency.
  /// Null for a market order.
  ///
  /// Reads [limitPrice] and only falls back to [price] when the column is null
  /// (rows placed before it existed, or by the legacy on-device path). Showing
  /// [price] in preference to this is what made a correct engine look broken:
  /// after a modification the two disagreed, and the card showed the value the
  /// engine was NOT matching.
  ///
  /// A pending US row carries USD in both columns, so no conversion is needed
  /// here — same reasoning as [displayPrice].
  double? get displayLimitPrice {
    if (orderType != 'limit') return null;
    return limitPrice ?? price;
  }

  /// Order value in the instrument's own currency.
  ///
  /// Deliberately recomputed from [displayPrice] rather than read from [total],
  /// because [total] switches to INR the moment the order executes.
  double get displayTotal => nativePrice != null ? nativePrice! * quantity : total;

  /// Realized P&L after this order's own charges. **This is the canonical figure**
  /// and the one that matches what the wallet actually moved by.
  ///
  /// [realizedPnl] as stored by the engine is GROSS: charges are written to their
  /// own columns and never subtracted from it. The portfolio's closed-position
  /// card, by contrast, subtracts them. Same trade, two numbers, which is what
  /// users were reporting as "the order says one thing and the portfolio says
  /// another". Both are now presented together, gross then charges then net, so
  /// the arithmetic is visible instead of having to be guessed.
  ///
  /// ponytail: scoped to THIS order, so on a round trip it carries the exit
  /// leg's charges only -- the entry leg was charged when it was placed and lives
  /// on a different row. The ceiling is that a full round-trip cost needs both
  /// rows; the upgrade path is a position-level ledger keyed by open/close pair.
  /// The UI wording below is careful not to claim otherwise.
  double get netRealizedPnl => realizedPnl - totalCharges;
}
