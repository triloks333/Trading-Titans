class User {
  final String id;
  final String email;
  final String name;
  final double walletBalance;
  final bool subscriptionActive;
  final DateTime createdAt;
  final double totalRealizedPnl;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.walletBalance,
    required this.subscriptionActive,
    required this.createdAt,
    required this.totalRealizedPnl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String? ?? '',
      walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      subscriptionActive: json['subscription_active'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      totalRealizedPnl: (json['total_realized_pnl'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'wallet_balance': walletBalance,
      'subscription_active': subscriptionActive,
      'created_at': createdAt.toIso8601String(),
      'total_realized_pnl': totalRealizedPnl,
    };
  }
}
