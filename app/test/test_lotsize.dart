import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/services/fo_instruments_service.dart';

class TestLocalStorage extends LocalStorage {
  const TestLocalStorage();
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<bool> hasAccessToken() async => false;
  @override
  Future<void> persistSession(String session) async {}
  @override
  Future<void> removeSession() async {}
  @override
  Future<void> removePersistedSession() async {}
}

void main() {
  test('test lot size', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: 'https://bftvimnhpoiuoyryyiff.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4NzU1NDQsImV4cCI6MjA5NTQ1MTU0NH0.TJHsgNbsolYMx50EuQQmdgLMaznGdV11e8pVMQaQ2ak',
      authOptions: const FlutterAuthClientOptions(
        localStorage: TestLocalStorage(),
      ),
    );

    final service = FoInstrumentsService();
    final lotSize = await service.getLotSize('NSE:FEDERALBNK-EQ-2026-06-25-305-CE');
    print('RESOLVED LOT SIZE VALUE: $lotSize');
    expect(lotSize, 2500);
  });
}
