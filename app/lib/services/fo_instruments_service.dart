import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class FoInstrument {
  final int instrumentToken;
  final int? exchangeToken;
  final String tradingsymbol;
  final String exchange;
  final String underlying;
  final String instrumentType;
  final DateTime expiryDate;
  final double strikePrice;
  final int lotSize;
  final double tickSize;

  FoInstrument({
    required this.instrumentToken,
    this.exchangeToken,
    required this.tradingsymbol,
    required this.exchange,
    required this.underlying,
    required this.instrumentType,
    required this.expiryDate,
    required this.strikePrice,
    required this.lotSize,
    required this.tickSize,
  });

  factory FoInstrument.fromJson(Map<String, dynamic> json) {
    return FoInstrument(
      instrumentToken: json['instrument_token'] as int,
      exchangeToken: json['exchange_token'] as int?,
      tradingsymbol: json['tradingsymbol'] as String,
      exchange: json['exchange'] as String,
      underlying: json['underlying'] as String,
      instrumentType: json['instrument_type'] as String,
      expiryDate: DateTime.parse(json['expiry_date'] as String),
      strikePrice: (json['strike_price'] as num).toDouble(),
      lotSize: json['lot_size'] as int? ?? 1,
      tickSize: (json['tick_size'] as num?)?.toDouble() ?? 0.05,
    );
  }
}

class FoInstrumentsService {
  static final FoInstrumentsService _instance = FoInstrumentsService._internal();
  factory FoInstrumentsService() => _instance;
  FoInstrumentsService._internal();

  final SupabaseClient _client = SupabaseService().client;

  // Local cache to avoid querying Supabase repeatedly for the same underlyings
  final Map<String, List<FoInstrument>> _underlyingCache = {};

  /// Extracts the base underlying stock/index symbol from any contract symbol format
  static String extractUnderlying(String symbol) {
    var s = symbol.toUpperCase().trim();
    if (s.startsWith('NSE:')) {
      s = s.substring(4);
    }
    if (s.startsWith('BSE:')) {
      s = s.substring(4);
    }
    
    // Strip segment suffix from symbol (e.g. FEDERALBNK-EQ -> FEDERALBNK)
    s = s.replaceAll('-EQ-', '-');
    if (s.endsWith('-EQ')) {
      s = s.substring(0, s.length - 3);
    }
    
    // Handle space-separated: "HDFCBANK JUN FUT" -> "HDFCBANK"
    if (s.contains(' ')) {
      s = s.split(' ')[0];
    }
    
    // Handle hyphen-separated: "HDFCBANK-2026-06-25-760-CE" -> "HDFCBANK"
    if (s.contains('-')) {
      s = s.split('-')[0];
    }
    
    // Map index symbols to underlying name used in database
    if (s == '^NSEI' || s == 'NSEI' || s == 'NIFTY50') {
      return 'NIFTY';
    }
    if (s == '^NSEBANK' || s == 'NSEBANK') {
      return 'BANKNIFTY';
    }
    if (s == '^BSESN' || s == 'SENSEX') {
      return 'SENSEX';
    }
    
    // Concatenated symbol like "HDFCBANK26JUNFUT": extract characters before the first digit
    final firstDigitIndex = s.indexOf(RegExp(r'\d'));
    if (firstDigitIndex > 0) {
      s = s.substring(0, firstDigitIndex);
    }
    
    return s;
  }

  static String? _extractMonth(String symbol) {
    final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    for (final month in months) {
      if (symbol.toUpperCase().contains(month)) {
        return month;
      }
    }
    return null;
  }

  static int _monthNumber(String month) {
    final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months.indexOf(month.toUpperCase()) + 1;
  }

  /// Fetches and caches instruments for a given underlying index/stock (e.g. NIFTY, SBIN)
  Future<List<FoInstrument>> _getInstrumentsForUnderlying(String underlying) async {
    final cleanUnderlying = underlying.toUpperCase().trim();
    if (_underlyingCache.containsKey(cleanUnderlying)) {
      return _underlyingCache[cleanUnderlying]!;
    }

    try {
      var prefix = cleanUnderlying;
      // Resolve index mapping if needed
      if (cleanUnderlying == 'NIFTY') {
        prefix = 'NIFTY';
      } else if (cleanUnderlying == 'BANKNIFTY') {
        prefix = 'BANKNIFTY';
      } else if (cleanUnderlying == 'FINNIFTY') {
        prefix = 'FINNIFTY';
      } else if (cleanUnderlying == 'MIDCPNIFTY') {
        prefix = 'MIDCPNIFTY';
      } else if (cleanUnderlying == 'SENSEX') {
        prefix = 'SENSEX';
      }

      final response = await _client
          .from('instruments')
          .select()
          .inFilter('instrument_type', ['OPTION', 'FUTURE'])
          .like('symbol', 'NSE:$prefix*');

      final list = (response as List<dynamic>)
          .map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            return FoInstrument(
              instrumentToken: int.tryParse(map['fyers_token'] as String? ?? '0') ?? 0,
              exchangeToken: null,
              tradingsymbol: (map['symbol'] as String? ?? '').replaceFirst('NSE:', ''),
              exchange: map['exchange'] as String? ?? 'NFO',
              underlying: cleanUnderlying,
              instrumentType: map['instrument_type'] as String? ?? 'OPTION',
              expiryDate: map['expiry_date'] != null 
                  ? DateTime.tryParse(map['expiry_date'] as String) ?? DateTime.now() 
                  : DateTime.now(),
              strikePrice: (map['strike_price'] as num?)?.toDouble() ?? 0.0,
              lotSize: (map['lot_size'] as num?)?.toInt() ?? 1,
              tickSize: (map['tick_size'] as num?)?.toDouble() ?? 0.05,
            );
          })
          .toList();

      if (list.isNotEmpty) {
        _underlyingCache[cleanUnderlying] = list;
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching instruments for $underlying: $e');
      return [];
    }
  }

  /// Standard exchange lot sizes for major index derivatives
  static int defaultLotSizeForUnderlying(String underlying) {
    final u = underlying.toUpperCase().trim();
    switch (u) {
      case 'NIFTY':
        return 75;
      case 'BANKNIFTY':
        return 30;
      case 'FINNIFTY':
        return 65;
      case 'MIDCPNIFTY':
        return 120;
      case 'SENSEX':
        return 20;
      case 'BANKEX':
        return 15;
      default:
        return 1;
    }
  }

  /// Get lot size for a given symbol (which could be a contract symbol or underlying symbol)
  Future<int> getLotSize(String symbol) async {
    final underlying = extractUnderlying(symbol);
    final instruments = await _getInstrumentsForUnderlying(underlying);
    if (instruments.isEmpty) return defaultLotSizeForUnderlying(underlying);

    var cleanSymbol = symbol.toUpperCase().trim();
    if (cleanSymbol.startsWith('NSE:')) {
      cleanSymbol = cleanSymbol.substring(4);
    }
    cleanSymbol = cleanSymbol.replaceAll('-EQ-', '-');

    // 1. If it's a hyphen-separated option (e.g. HDFCBANK-2026-06-25-760-CE)
    if (cleanSymbol.contains('-')) {
      final parts = cleanSymbol.split('-');
      if (parts.length >= 4) {
        final expiryStr = '${parts[1]}-${parts[2].padLeft(2, '0')}-${parts[3].padLeft(2, '0')}';
        final match = instruments.where((e) => e.expiryDate.toIso8601String().startsWith(expiryStr));
        if (match.isNotEmpty && match.first.lotSize > 1) {
          return match.first.lotSize;
        }
      }
    }

    // 2. If it is a space-separated future (e.g. HDFCBANK JUN FUT)
    if (cleanSymbol.contains(' ')) {
      final month = _extractMonth(cleanSymbol);
      if (month != null) {
        final monthNum = _monthNumber(month);
        final match = instruments.where((e) => e.expiryDate.month == monthNum);
        if (match.isNotEmpty && match.first.lotSize > 1) {
          return match.first.lotSize;
        }
      }
    }

    // Default to the first instrument's lot size (which is usually the current month/active contract)
    if (instruments.isNotEmpty && instruments.first.lotSize > 1) {
      return instruments.first.lotSize;
    }
    return defaultLotSizeForUnderlying(underlying);
  }

  /// Get list of available expiry dates for a given underlying.
  ///
  /// Expired contracts are filtered out HERE rather than in
  /// [_getInstrumentsForUnderlying], and that placement is deliberate.
  /// `instruments` never drops a row, so the underlying's contract list reaches
  /// back months; this method feeds the expiry picker, so without a filter the
  /// app offered contracts that settled long ago. [getLotSize] shares the same
  /// cached list and must keep seeing expired rows, because an open position on
  /// an expired contract still has to resolve its real lot size at settlement —
  /// filtering upstream would silently fall back to a lot size of 1 and settle
  /// those positions at a fraction of their value.
  Future<List<DateTime>> getAvailableExpiries(String underlying) async {
    final cleanUnderlying = extractUnderlying(underlying);
    final instruments = await _getInstrumentsForUnderlying(cleanUnderlying);
    // Date-only comparison: a contract is tradeable through its whole expiry
    // day, so `today` itself must pass.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiries = instruments
        .map((e) => e.expiryDate)
        .where((d) => !DateTime(d.year, d.month, d.day).isBefore(today))
        .toSet()
        .toList();
    expiries.sort();
    return expiries;
  }

  /// Get list of available strike prices for a given underlying and expiry date
  Future<List<double>> getAvailableStrikes(String underlying, DateTime expiry) async {
    final cleanUnderlying = extractUnderlying(underlying);
    final expiryStr = expiry.toIso8601String().split('T')[0];
    final instruments = await _getInstrumentsForUnderlying(cleanUnderlying);
    final strikes = instruments
        .where((e) => e.expiryDate.toIso8601String().split('T')[0] == expiryStr && e.strikePrice > 0)
        .map((e) => e.strikePrice)
        .toSet()
        .toList();
    strikes.sort();
    return strikes;
  }

  /// Resolve exact tradingsymbol or contract details
  Future<FoInstrument?> getInstrument(String tradingsymbol) async {
    final cleanSym = tradingsymbol.toUpperCase().trim();
    try {
      final response = await _client
          .from('instruments')
          .select()
          .or('symbol.eq.$cleanSym,symbol.eq.NSE:$cleanSym')
          .maybeSingle();

      if (response == null) return null;
      final map = Map<String, dynamic>.from(response as Map);
      
      final underlying = extractUnderlying(cleanSym);

      return FoInstrument(
        instrumentToken: int.tryParse(map['fyers_token'] as String? ?? '0') ?? 0,
        exchangeToken: null,
        tradingsymbol: (map['symbol'] as String? ?? '').replaceFirst('NSE:', ''),
        exchange: map['exchange'] as String? ?? 'NFO',
        underlying: underlying,
        instrumentType: map['instrument_type'] as String? ?? 'OPTION',
        expiryDate: map['expiry_date'] != null 
            ? DateTime.tryParse(map['expiry_date'] as String) ?? DateTime.now() 
            : DateTime.now(),
        strikePrice: (map['strike_price'] as num?)?.toDouble() ?? 0.0,
        lotSize: (map['lot_size'] as num?)?.toInt() ?? 1,
        tickSize: (map['tick_size'] as num?)?.toDouble() ?? 0.05,
      );
    } catch (e) {
      debugPrint('Error fetching instrument $tradingsymbol: $e');
      return null;
    }
  }

  /// Helper to check if a specific expiry date is a weekly expiry
  /// For index options, we check if it is not the last Thursday (or expiry day) of the month.
  bool isWeeklyExpiry(String underlying, DateTime expiry) {
    // Determine the last day of the month for this expiry
    final year = expiry.year;
    final month = expiry.month;
    
    // Find the last day of the month
    final lastDay = DateTime(year, month + 1, 0);
    
    // NSE/BSE expiries: NSE indices are usually Tuesday/Thursday, BSE indices are Monday/Friday/etc.
    // Stock options expire on the last Thursday of the month.
    // To check if a date is the monthly expiry, we look for the last occurrence of that specific weekday in the month.
    final expiryWeekday = expiry.weekday;
    
    // Calculate the last occurrence of this weekday in the month
    var monthlyExpiry = lastDay;
    while (monthlyExpiry.weekday != expiryWeekday) {
      monthlyExpiry = monthlyExpiry.subtract(const Duration(days: 1));
    }
    
    // If the given expiry date is equal to the monthly expiry date, it's NOT a weekly expiry (it's monthly).
    final isMonthly = expiry.year == monthlyExpiry.year && 
                     expiry.month == monthlyExpiry.month && 
                     expiry.day == monthlyExpiry.day;
    
    return !isMonthly;
  }
}
