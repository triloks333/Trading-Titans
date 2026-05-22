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
  });

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
