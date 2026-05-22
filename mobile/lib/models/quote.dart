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
  });

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
    };
  }
}
