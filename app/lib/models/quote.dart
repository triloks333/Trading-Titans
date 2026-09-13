class Quote {
  final String symbol;
  final String yfSymbol;
  final String name;
  final double price;
  final double previousClose;
  final double change;
  final double changePct;
  final String currency;
  final String market;
  final String? source;
  final String? displayName;
  final String? category;
  
  final double? dayLow;
  final double? dayHigh;
  final double? open;
  final int? volume;
  final double? avgTradePrice;
  final int? lastTradedQuantity;
  final String? lastTradedTime;
  final double? lowerCircuit;
  final double? upperCircuit;

  /// USD to INR rate, present only on quotes priced in a foreign currency.
  /// Indicative: the binding rate is the one the order engine records at fill.
  final double? fxRate;

  Quote({
    required this.symbol,
    required this.yfSymbol,
    required this.name,
    required this.price,
    required this.previousClose,
    required this.change,
    required this.changePct,
    required this.currency,
    required this.market,
    this.source,
    this.displayName,
    this.category,
    this.dayLow,
    this.dayHigh,
    this.open,
    this.volume,
    this.avgTradePrice,
    this.lastTradedQuantity,
    this.lastTradedTime,
    this.lowerCircuit,
    this.upperCircuit,
    this.fxRate,
  });

  /// True when this instrument's prices are not in rupees.
  bool get isNativeCurrency => currency != 'INR';

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      symbol: json['symbol'] as String? ?? '',
      yfSymbol: json['yf_symbol'] as String? ?? '',
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      previousClose: (json['previous_close'] as num?)?.toDouble() ?? 0.0,
      change: (json['change'] as num?)?.toDouble() ?? 0.0,
      changePct: (json['change_pct'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'INR',
      market: json['market'] as String? ?? 'stock',
      source: json['source'] as String?,
      displayName: json['display_name'] as String?,
      category: json['category'] as String?,
      dayLow: (json['day_low'] as num?)?.toDouble(),
      dayHigh: (json['day_high'] as num?)?.toDouble(),
      open: (json['open'] as num?)?.toDouble(),
      volume: (json['volume'] as num?)?.toInt(),
      avgTradePrice: (json['avg_trade_price'] as num?)?.toDouble(),
      lastTradedQuantity: (json['last_traded_quantity'] as num?)?.toInt(),
      lastTradedTime: json['last_traded_time'] as String?,
      lowerCircuit: (json['lower_circuit'] as num?)?.toDouble(),
      upperCircuit: (json['upper_circuit'] as num?)?.toDouble(),
      fxRate: (json['fx_rate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'yf_symbol': yfSymbol,
      'name': name,
      'price': price,
      'previous_close': previousClose,
      'change': change,
      'change_pct': changePct,
      'currency': currency,
      'market': market,
      'source': source,
      'display_name': displayName,
      'category': category,
      'day_low': dayLow,
      'day_high': dayHigh,
      'open': open,
      'volume': volume,
      'avg_trade_price': avgTradePrice,
      'last_traded_quantity': lastTradedQuantity,
      'last_traded_time': lastTradedTime,
      'lower_circuit': lowerCircuit,
      'upper_circuit': upperCircuit,
      'fx_rate': fxRate,
    };
  }
}
