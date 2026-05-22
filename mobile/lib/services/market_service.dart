import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/supabase_config.dart';
import '../models/quote.dart';

class MarketService {
  static const String _functionsBase =
      'https://zclkzgjmcisjinnuibrh.supabase.co/functions/v1';
  static const Duration _timeout = Duration(seconds: 20);

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $supabaseAnonKey',
      };

  static Future<List<Quote>> getMarketOverview() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_functionsBase/market-overview'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => Quote.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Quote?> quote(String symbol, String market) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '$_functionsBase/market-quote?symbol=$symbol&market=$market'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return Quote.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> search(
      String query, String market) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '$_functionsBase/market-search?q=$query&market=$market'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getHistory(
      String symbol, String market, String range) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_functionsBase/market-history?symbol=$symbol&market=$market&range=$range',
            ),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['points'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> simulateWhatIf(
      String symbol, String market, double amount, int years) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_functionsBase/whatif'),
            headers: _headers,
            body: jsonEncode({
              'symbol': symbol,
              'market': market,
              'amount': amount,
              'years_ago': years,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
