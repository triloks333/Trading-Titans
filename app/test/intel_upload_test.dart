import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/intel/intel_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('upload batches unsent events once, keeps them on failure, survives reload', () async {
    final store = IntelStore();
    await store.load();
    for (var i = 0; i < 5; i++) {
      store.add('tap', {'i': i});
    }

    // Failure: nothing marked sent.
    await expectLater(store.upload((_) async => throw Exception('offline'), max: 3), throwsException);
    expect(store.events.where((e) => !e.synced).length, 5);

    final sent = <int>[];
    Future<void> send(List<IntelEvent> b) async => sent.addAll(b.map((e) => e.props['i'] as int));

    expect(await store.upload(send, max: 3), 3);
    expect(await store.upload(send, max: 3), 2);
    expect(await store.upload(send, max: 3), 0);
    expect(sent, [0, 1, 2, 3, 4]);

    // The cursor (synced flag) is persisted, so a restart does not resend.
    final reloaded = IntelStore();
    await reloaded.load();
    expect(await reloaded.upload(send), 0);
  });
}
