import 'dart:io';
import 'dart:typed_data';

/// Result of preparing a file for upload.
class PackedBytes {
  const PackedBytes(this.bytes, this.compressed);
  final Uint8List bytes;
  final bool compressed;
}

/// gzip a document only when that actually saves space. JPEG/PNG/MP4/ZIP are
/// already compressed, so re-packing them would grow the object instead.
///
/// ponytail: single-shot gzip, no chunking. Ceiling: whole file is held in
/// memory, which is fine for the documents this vault stores (tens of MB). Move
/// to a streaming codec if large video uploads are ever allowed.
PackedBytes packForUpload(Uint8List raw) {
  if (raw.length < 1024) return PackedBytes(raw, false);
  final zipped = Uint8List.fromList(gzip.encode(raw));
  return zipped.length < raw.length * 0.95
      ? PackedBytes(zipped, true)
      : PackedBytes(raw, false);
}

/// Inverse of [packForUpload], driven by the stored `compressed` flag.
Uint8List unpackDownload(Uint8List stored, {required bool compressed}) =>
    compressed ? Uint8List.fromList(gzip.decode(stored)) : stored;
