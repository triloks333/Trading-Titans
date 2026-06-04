class CandleData {
  final int timestamp;
  final double open;
  final double high;
  final double low;
  final double close;

  CandleData({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory CandleData.fromJson(Map<String, dynamic> json) {
    return CandleData(
      timestamp: (json['t'] as num).toInt(),
      open: (json['o'] as num).toDouble(),
      high: (json['h'] as num).toDouble(),
      low: (json['l'] as num).toDouble(),
      close: (json['c'] as num).toDouble(),
    );
  }

  bool get isUp => close >= open;
}
