import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'scan_contract.dart';

ScanBackend createScanBackend() => _NativeScanBackend();

class _NativeScanBackend implements ScanBackend {
  @override
  bool get isSupported =>
      (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<String> recognize(
    String imagePath, {
    required String language,
    Uint8List? imageBytes,
    ScanProgress? onProgress,
  }) async {
    if (!isSupported) {
      throw const ScanException(
        ScanErrorCode.unsupportedPlatform,
        'Fotoerkennung ist in der iPhone-, iPad- und Android-App verfügbar. '
        'Suche hier mit dem Kartennamen oder der Nummer unten auf der Karte.',
      );
    }
    if (imagePath.trim().isEmpty) {
      throw const ScanException(
        ScanErrorCode.invalidImage,
        'Kein Foto ausgewählt. Fotografiere die Karte oder wähle ein Bild.',
      );
    }

    final recognizer = TextRecognizer(script: _scriptFor(language));
    try {
      final image = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(image);
      if (recognized.text.trim().isEmpty) {
        throw const ScanException(
          ScanErrorCode.noText,
          'Kein Text erkannt. Fotografiere die ganze Vorderseite scharf, '
          'gerade und ohne Lichtreflexe. Wähle die passende Kartensprache.',
        );
      }
      return recognized.text;
    } on ScanException {
      rethrow;
    } on PlatformException {
      throw const ScanException(
        ScanErrorCode.recognitionFailed,
        'Das Foto konnte nicht gelesen werden. Nimm ein neues Foto auf '
        'oder suche mit der Kartennummer.',
      );
    } on MissingPluginException {
      throw const ScanException(
        ScanErrorCode.unsupportedPlatform,
        'Die Fotoerkennung ist in dieser Installation nicht verfügbar. '
        'Starte die native App neu oder suche mit der Kartennummer.',
      );
    } finally {
      // Releasing a native resource must not hide a useful recognition error.
      try {
        await recognizer.close();
      } on PlatformException {
        // A failed initialization may leave no native recognizer to close.
      } on MissingPluginException {
        // The native plugin was not registered in this installation.
      }
    }
  }

  static TextRecognitionScript _scriptFor(String language) {
    final code = language.toLowerCase().replaceAll('_', '-').split('-').first;
    return switch (code) {
      'ja' || 'jp' => TextRecognitionScript.japanese,
      'zh' || 'cn' => TextRecognitionScript.chinese,
      'ko' || 'kr' => TextRecognitionScript.korean,
      'hi' || 'mr' || 'ne' => TextRecognitionScript.devanagiri,
      'de' ||
      'en' ||
      'fr' ||
      'es' ||
      'it' ||
      'pt' ||
      'nl' ||
      'id' ||
      'ms' ||
      'vi' ||
      'tr' ||
      'pl' => TextRecognitionScript.latin,
      _ => throw const ScanException(
        ScanErrorCode.unsupportedLanguage,
        'Diese Schrift wird von der Fotoerkennung noch nicht unterstützt. '
        'Suche mit der Nummer unten auf der Karte und bestätige die Sprache.',
      ),
    };
  }
}
