import 'dart:typed_data';
import 'scan_contract.dart';

ScanBackend createScanBackend() => _UnsupportedScanBackend();

class _UnsupportedScanBackend implements ScanBackend {
  @override
  bool get isSupported => false;
  @override
  Future<String> recognize(
    String imagePath, {
    required String language,
    Uint8List? imageBytes,
    ScanProgress? onProgress,
  }) async => throw const ScanException(
    ScanErrorCode.unsupportedPlatform,
    'Nutze die Fotoerkennung im Browser oder in der iPhone-, iPad- oder Android-App.',
  );
}
