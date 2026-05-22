import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/supabase_config.dart';
import '../models/quote.dart';

class ApiService {
  static const String _functionsBase =
      'https://zclkzgjmcisjinnuibrh.supabase.co/functions/v1';

  String? _token;

  void setToken(String token) {
    _token = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $supabaseAnonKey',
        if (_token != null) 'x-auth-token': _token!,
      };

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_functionsBase/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setToken(data['access_token']);
      return data;
    }
    throw Exception('Failed to login: ${response.body}');
  }

  Future<List<Quote>> getMarketOverview() async {
    final response = await http.get(
        Uri.parse('$_functionsBase/market-overview'),
        headers: _headers);
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => Quote.fromJson(e)).toList();
    }
    throw Exception('Failed to load market overview');
  }

  Future<Quote> getQuote(String symbol, String market) async {
    final response = await http.get(
        Uri.parse(
            '$_functionsBase/market-quote?symbol=$symbol&market=$market'),
        headers: _headers);
    if (response.statusCode == 200) {
      return Quote.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to load quote');
  }

  Future<List<Map<String, dynamic>>> searchMarket(
      String query, String market) async {
    final response = await http.get(
        Uri.parse('$_functionsBase/market-search?q=$query&market=$market'),
        headers: _headers);
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to search market');
  }

  Future<Map<String, dynamic>> getMarketHistory(
      String symbol, String market, String range) async {
    final response = await http.get(
        Uri.parse(
            '$_functionsBase/market-history?symbol=$symbol&market=$market&range=$range'),
        headers: _headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load history');
  }
}
