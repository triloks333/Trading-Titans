import 'package:flutter/material.dart';
import 'supabase_service.dart';
import '../models/user.dart' as app_models;

class AuthService extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService();

  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

  app_models.User? _user;
  app_models.User? get user => _user;

  bool get isAuthenticated => _user != null;

  Future<void> initialize() async {
    _user = await _supabase.getUserProfile();
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    await _supabase.signIn(email: email, password: password);
    _user = await _supabase.getUserProfile();
    notifyListeners();
  }

  Future<void> register(String email, String password, String name, {String? referralCode}) async {
    await _supabase.signUp(email: email, password: password, name: name, referralCode: referralCode);
    // Profile may not exist immediately after signup (DB trigger race condition).
    // Retry a few times with a short delay.
    for (int i = 0; i < 5; i++) {
      _user = await _supabase.getUserProfile();
      if (_user != null) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _supabase.signOut();
    _user = null;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    _user = await _supabase.getUserProfile();
    notifyListeners();
  }
}
