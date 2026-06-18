class FoPosition {
  final String id;
  final String userId;
  final String symbol;
  final String instrumentType; 
  final String optionType;      
  final double strikePrice;   
  final DateTime expiry;
  final int netQty;         // Typed as int (whole lots)
  final int lotSize;            
  final double avgEntryPrice;   
  final double marginBlocked;   
  final DateTime? createdAt;

  FoPosition({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.instrumentType,
    required this.optionType,
    required this.strikePrice,
    required this.expiry,
    required this.netQty,
    required this.lotSize,
    required this.avgEntryPrice,
    required this.marginBlocked,
    this.createdAt,
  });

  double unrealizedPnl(double currentPrice) {
    final totalUnits = netQty.abs() * lotSize;
    return (netQty > 0)
        ? (currentPrice - avgEntryPrice) * totalUnits
        : (avgEntryPrice - currentPrice) * totalUnits;
  }

  double unrealizedPnlPct(double currentPrice) {
    if (netQty > 0 && instrumentType == 'OPTION') {
      return ((currentPrice - avgEntryPrice) / avgEntryPrice) * 100;
    }
    if (marginBlocked == 0) return 0.0;
    return (unrealizedPnl(currentPrice) / marginBlocked) * 100;
  }

  factory FoPosition.fromJson(Map<String, dynamic> json) {
    return FoPosition(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      instrumentType: json['instrument_type'] as String? ?? 'OPTION',
      optionType: json['option_type'] as String? ?? '',
      strikePrice: (json['strike_price'] as num?)?.toDouble() ?? 0.0,
      expiry: DateTime.parse(json['expiry_date'] as String),
      netQty: (json['net_qty'] as num?)?.toInt() ?? 0,
      lotSize: (json['lot_size'] as num?)?.toInt() ?? 1,
      avgEntryPrice: (json['avg_entry_price'] as num?)?.toDouble() ?? 0.0,
      marginBlocked: (json['margin_blocked'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'symbol': symbol,
      'instrument_type': instrumentType,
      'option_type': optionType,
      'strike_price': strikePrice,
      'expiry_date': expiry.toIso8601String().split('T')[0],
      'net_qty': netQty,
      'lot_size': lotSize,
      'avg_entry_price': avgEntryPrice,
      'margin_blocked': marginBlocked,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
