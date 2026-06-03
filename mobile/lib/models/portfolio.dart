class Holding {
  final String symbol;
  final String name;
  final String market;
  final double quantity;
  final double avgPrice;
  final double currentPrice;
  final double previousClose;
  final double invested;
  final double current;
  final double pnl;
  final double pnlPct;
  final double dayPnl;
  final double dayPnlPct;

  // F&O-specific fields
  final String instrumentType; // 'EQUITY' | 'OPTION'
  final String? optionType;    // 'CE' | 'PE' (null for equity)
  final double? strikePrice;   // null for equity
  final String? expiryDate;    // e.g. '2026-06-05' (null for equity)
  final String productType;    // 'NRML' | 'MIS' | 'CNC' (CNC = delivery for equity)

  Holding({
    required this.symbol,
    required this.name,
    required this.market,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
    required this.previousClose,
    required this.invested,
    required this.current,
    required this.pnl,
    required this.pnlPct,
    required this.dayPnl,
    required this.dayPnlPct,
    this.instrumentType = 'EQUITY',
    this.optionType,
    this.strikePrice,
    this.expiryDate,
    this.productType = 'CNC',
  });

  // Convenience getters
  bool get isOption => instrumentType == 'OPTION';
  bool get isEquity => instrumentType == 'EQUITY';
  bool get isLong => quantity > 0;
  bool get isShort => quantity < 0;
  String get positionTag => isLong ? 'LONG' : 'SHORT';
  String get displayName {
    if (isOption && optionType != null && strikePrice != null) {
      return '$symbol ${strikePrice!.toStringAsFixed(0)} $optionType';
    }
    return name.isNotEmpty ? name : symbol;
  }

  /// Returns time remaining until expiry as a human-readable string
  String? get expiryCountdown {
    if (expiryDate == null) return null;
    final expiry = DateTime.tryParse(expiryDate!);
    if (expiry == null) return null;
    final now = DateTime.now();
    final expiryEod = DateTime(expiry.year, expiry.month, expiry.day, 15, 30);
    final diff = expiryEod.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }

  factory Holding.fromJson(Map<String, dynamic> json) {
    return Holding(
      symbol: json['symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      market: json['market'] as String? ?? 'stock',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      avgPrice: (json['avg_price'] as num?)?.toDouble() ?? 0.0,
      currentPrice: (json['current_price'] as num?)?.toDouble() ?? 0.0,
      previousClose: (json['previous_close'] as num?)?.toDouble() ?? (json['current_price'] as num?)?.toDouble() ?? 0.0,
      invested: (json['invested'] as num?)?.toDouble() ?? 0.0,
      current: (json['current'] as num?)?.toDouble() ?? 0.0,
      pnl: (json['pnl'] as num?)?.toDouble() ?? 0.0,
      pnlPct: (json['pnl_pct'] as num?)?.toDouble() ?? 0.0,
      dayPnl: (json['day_pnl'] as num?)?.toDouble() ?? 0.0,
      dayPnlPct: (json['day_pnl_pct'] as num?)?.toDouble() ?? 0.0,
      instrumentType: json['instrument_type'] as String? ?? 'EQUITY',
      optionType: json['option_type'] as String?,
      strikePrice: (json['strike_price'] as num?)?.toDouble(),
      expiryDate: json['expiry_date'] as String?,
      productType: json['product_type'] as String? ?? 'CNC',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'name': name,
      'market': market,
      'quantity': quantity,
      'avg_price': avgPrice,
      'current_price': currentPrice,
      'previous_close': previousClose,
      'invested': invested,
      'current': current,
      'pnl': pnl,
      'pnl_pct': pnlPct,
      'day_pnl': dayPnl,
      'day_pnl_pct': dayPnlPct,
      'instrument_type': instrumentType,
      'option_type': optionType,
      'strike_price': strikePrice,
      'expiry_date': expiryDate,
      'product_type': productType,
    };
  }
}

class Portfolio {
  final double walletBalance;
  final double investedValue;
  final double currentValue;
  final double unrealizedPnl;
  final double unrealizedPnlPct;
  final double realizedPnl;
  final double dayPnl;
  final List<Holding> holdings;

  Portfolio({
    required this.walletBalance,
    required this.investedValue,
    required this.currentValue,
    required this.unrealizedPnl,
    required this.unrealizedPnlPct,
    required this.realizedPnl,
    required this.dayPnl,
    required this.holdings,
  });

  // Convenience getters for filtered lists
  List<Holding> get equityHoldings =>
      holdings.where((h) => h.isEquity).toList();

  List<Holding> get optionPositions =>
      holdings.where((h) => h.isOption).toList();

  factory Portfolio.fromJson(Map<String, dynamic> json) {
    return Portfolio(
      walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      investedValue: (json['invested_value'] as num?)?.toDouble() ?? 0.0,
      currentValue: (json['current_value'] as num?)?.toDouble() ?? 0.0,
      unrealizedPnl: (json['unrealized_pnl'] as num?)?.toDouble() ?? 0.0,
      unrealizedPnlPct: (json['unrealized_pnl_pct'] as num?)?.toDouble() ?? 0.0,
      realizedPnl: (json['realized_pnl'] as num?)?.toDouble() ?? 0.0,
      dayPnl: (json['day_pnl'] as num?)?.toDouble() ?? 0.0,
      holdings: (json['holdings'] as List<dynamic>?)
              ?.map((e) => Holding.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wallet_balance': walletBalance,
      'invested_value': investedValue,
      'current_value': currentValue,
      'unrealized_pnl': unrealizedPnl,
      'unrealized_pnl_pct': unrealizedPnlPct,
      'realized_pnl': realizedPnl,
      'day_pnl': dayPnl,
      'holdings': holdings.map((e) => e.toJson()).toList(),
    };
  }
}
