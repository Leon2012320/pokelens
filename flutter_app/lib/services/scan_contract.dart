import 'dart:typed_data';

enum ScanErrorCode {
  unsupportedPlatform,
  unsupportedLanguage,
  invalidImage,
  noText,
  recognitionFailed,
  timedOut,
}

class ScanException implements Exception {
  const ScanException(this.code, this.message);
  final ScanErrorCode code;
  final String message;
  @override
  String toString() => message;
}

typedef ScanProgress = void Function(String message);

abstract interface class ScanBackend {
  bool get isSupported;
  Future<String> recognize(
    String imagePath, {
    required String language,
    Uint8List? imageBytes,
    ScanProgress? onProgress,
  });
}
