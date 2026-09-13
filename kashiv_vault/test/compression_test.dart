import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kashiv_vault/core/compression.dart';

void main() {
  test('compressible document shrinks and survives the round trip', () {
    final raw = Uint8List.fromList(
      List.generate(40000, (i) => 'GST invoice line $i\n'.codeUnitAt(i % 5)),
    );

    final packed = packForUpload(raw);

    expect(packed.compressed, isTrue, reason: 'text must compress');
    expect(packed.bytes.length, lessThan(raw.length));
    expect(unpackDownload(packed.bytes, compressed: true), equals(raw));
  });

  test('already-compressed payloads are stored untouched', () {
    final random = Random(7);
    final noise = Uint8List.fromList(
      List.generate(40000, (_) => random.nextInt(256)),
    );

    final packed = packForUpload(noise);

    expect(packed.compressed, isFalse, reason: 'gzip cannot beat random bytes');
    expect(packed.bytes, same(noise));
    expect(unpackDownload(packed.bytes, compressed: false), equals(noise));
  });

  test('tiny files skip gzip framing overhead', () {
    final tiny = Uint8List.fromList(List.filled(200, 65));

    expect(packForUpload(tiny).compressed, isFalse);
  });
}
