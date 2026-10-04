import 'dart:js_interop';
import 'dart:typed_data';
import 'scan_contract.dart';

@JS('pokeLensRecognizePhoto')
external JSPromise<JSString> _recognizePhoto(
  JSUint8Array bytes,
  JSString language,
  JSFunction progress,
);

ScanBackend createScanBackend() => _BrowserScanBackend();

class _BrowserScanBackend implements ScanBackend {
  @override
  bool get isSupported => true;

  @override
  Future<String> recognize(
    String imagePath, {
    required String language,
    Uint8List? imageBytes,
    ScanProgress? onProgress,
  }) async {
    if (imageBytes == null || imageBytes.isEmpty) {
      throw const ScanException(
        ScanErrorCode.invalidImage,
        'Kein lesbares Foto ausgewählt. Wähle ein JPG-, PNG- oder WebP-Bild.',
      );
    }
    try {
      final progress = ((JSString message) => onProgress?.call(
        message.toDart,
      )).toJS;
      final text = await _recognizePhoto(
        imageBytes.toJS,
        language.toJS,
        progress,
      ).toDart;
      return text.toDart;
    } catch (error) {
      final message = error.toString();
      if (message.contains('OCR_TIMEOUT')) {
        throw const ScanException(
          ScanErrorCode.timedOut,
          'Die Fotoerkennung dauert zu lange. Prüfe deine Verbindung und versuche es erneut.',
        );
      }
      if (message.contains('OCR_INVALID_IMAGE')) {
        throw const ScanException(
          ScanErrorCode.invalidImage,
          'Dieses Bildformat konnte nicht geöffnet werden. Wähle ein JPG-, PNG- oder WebP-Bild.',
        );
      }
      throw const ScanException(
        ScanErrorCode.recognitionFailed,
        'Die Fotoerkennung konnte nicht gestartet werden. Beim ersten Scan müssen Sprachdaten geladen werden. Prüfe deine Verbindung und versuche es erneut.',
      );
    }
  }
}
