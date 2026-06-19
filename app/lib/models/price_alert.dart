/// A user-defined alert that fires a notification when a symbol's price
/// crosses [targetPrice] in the configured [direction].
class PriceAlert {
  final String id;
  final String symbol;
  final String market;
  final String? name;
  final double targetPrice;

  /// 'above' fires when price >= target; 'below' fires when price <= target.
  final String direction;

  /// Price at the moment the alert was created (informational).
  final double? referencePrice;

  /// 'active' | 'triggered' | 'cancelled'
  final String status;

  final DateTime? createdAt;
  final DateTime? triggeredAt;

  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.market,
    this.name,
    required this.targetPrice,
    required this.direction,
    this.referencePrice,
    required this.status,
    this.createdAt,
    this.triggeredAt,
  });

  bool get isAbove => direction == 'above';
  bool get isActive => status == 'active';

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    return PriceAlert(
      id: json['id'] as String,
      symbol: json['symbol'] as String? ?? '',
      market: json['market'] as String? ?? 'stock',
      name: json['name'] as String?,
      targetPrice: (json['target_price'] as num?)?.toDouble() ?? 0.0,
      direction: json['direction'] as String? ?? 'above',
      referencePrice: (json['reference_price'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      triggeredAt: json['triggered_at'] != null
          ? DateTime.tryParse(json['triggered_at'] as String)
          : null,
    );
  }
}
