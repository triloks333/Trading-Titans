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
    );
  }

  bool get isBuy => side == 'buy';
  bool get isPending => status == 'pending';
  bool get isExecuted => status == 'executed';
  bool get isCancelled => status == 'cancelled';
}
