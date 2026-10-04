import 'dart:typed_data';
import '../models/pokemon_card.dart';
import 'photo_rank_stub.dart'
    if (dart.library.js_interop) 'photo_rank_web.dart'
    as matching;
import 'scan_contract.dart';
import 'scan_backend_stub.dart'
    if (dart.library.io) 'scan_backend_native.dart'
    if (dart.library.js_interop) 'scan_backend_web.dart'
    as platform;
export 'scan_contract.dart';

class ScanResult {
  const ScanResult({
    required this.rawText,
    this.cardName,
    this.collectorNumber,
    this.nameCandidates = const [],
  });

  final String rawText;
  final String? cardName;
  final String? collectorNumber;
  final List<String> nameCandidates;

  String get suggestedQuery => collectorNumber ?? cardName ?? '';
}

class ScanService {
  ScanService({ScanBackend? backend})
    : _backend = backend ?? platform.createScanBackend();
  final ScanBackend _backend;
  bool get isSupported => _backend.isSupported;

  Future<List<PokemonCard>> rankCandidates(
    Uint8List image,
    List<PokemonCard> cards,
  ) async {
    final indices = await matching.rankCardImages(
      image,
      cards.map((card) => card.imageUrl ?? '').toList(),
    );
    return indices
        .where((index) => index >= 0 && index < cards.length)
        .map((index) => cards[index])
        .toList();
  }

  Future<ScanResult> recognize(
    String imagePath, {
    String language = 'de',
    Uint8List? imageBytes,
    ScanProgress? onProgress,
  }) async {
    final text = await _backend.recognize(
      imagePath,
      language: language,
      imageBytes: imageBytes,
      onProgress: onProgress,
    );
    if (text.trim().isEmpty) {
      throw const ScanException(
        ScanErrorCode.noText,
        'Kein Text erkannt. Fotografiere die ganze Vorderseite scharf, gerade und ohne Lichtreflexe. Wähle die passende Kartensprache.',
      );
    }
    final result = parseText(text);
    if (result.suggestedQuery.isEmpty) {
      throw const ScanException(
        ScanErrorCode.noText,
        'Keine lesbare Kartennummer oder kein Kartenname gefunden. Nimm das Foto näher und gerade auf oder suche manuell.',
      );
    }
    return result;
  }

  static final _collectorPattern = RegExp(
    r'(?<![A-Za-z0-9])([A-Za-z]{0,3}[0-9]{1,3})\s*[/⁄／]\s*'
    r'([A-Za-z]{0,3}[0-9]{2,3}|[A-Za-z]{1,3}-P)(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  static final _promoPattern = RegExp(
    r'\b((?:SWSH|SM|XY|BW|SVP)\s*\d{1,3})\b',
    caseSensitive: false,
  );
  static final _westernStage = RegExp(
    r'^(?:(?:basic|basis|basique|básico|basico|base|basic pokémon)|'
    r'(?:stage|phase|rang|niveau|fase|estágio|estagio)\s*[12])(?=\s|$)\s*[:|·-]?\s*',
    caseSensitive: false,
  );
  static final _asianStage = RegExp(
    r'^(?:たね|[12１２]進化|기본|[12]진화|基礎|基础|基本|[12][階阶][進进]化)\s*',
  );
  static final _hp = RegExp(
    r'(?:\b(?:HP|KP|PV|PS)\s*[:.]?\s*\d{1,4}|\d{1,4}\s*(?:HP|KP|PV|PS)\b)',
    caseSensitive: false,
  );
  static final _nonNameLine = RegExp(
    r'^(?:pok[eé]mon(?:\s+tcg)?|trading card game|trainer|trainerkarte|'
    r'trainer card|dresseur|entrenador|allenatore|treinador|energy|energie|'
    r'énergie|energía|energia|サポート|グッズ|トレーナーズ|에너지|트레이너|'
    r'HP|KP|PV|PS|VMAX|VSTAR|EX|GX|V)$|'
    r'^(?:evolves from|evolves into|entwickelt sich|entwicklung aus|'
    r'évolution de|evoluciona de|evolui de|si evolve da|'
    r'weakness|resistance|retreat|schwäche|resistenz|rückzug|'
    r'ability|fähigkeit|poké-power|poké-body|illustrator|illus\.|'
    r'©|copyright|no\.\s*\d|nr\.\s*\d)',
    caseSensitive: false,
  );
  static final _letters = RegExp(r'\p{L}', unicode: true);

  /// Extracts search candidates, retaining the original text for corrections.
  /// Collector numbers keep prefixes and leading zeros to distinguish subsets.
  static ScanResult parseText(String text) {
    // Normalize full-width digits without altering names or the raw OCR result.
    final normalized = text.replaceAllMapped(
      RegExp(r'[０-９]'),
      (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0xfee0),
    );
    final collector = _collectorPattern.firstMatch(normalized);
    final promo = _promoPattern.firstMatch(normalized);
    final number = collector != null
        ? '${collector[1]}/${collector[2]}'.toUpperCase()
        : promo?[1]?.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    String? bestName;
    final names = <String>[];
    var bestScore = -1;
    final lines = normalized.split(RegExp(r'[\r\n]+'));
    for (var i = 0; i < lines.length && i < 12; i++) {
      final original = lines[i].trim();
      var line = original
          .replaceFirst(_westernStage, '')
          .replaceFirst(_asianStage, '')
          .replaceAll(_hp, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[\s|·:★☆]+|[\s|·:★☆]+$'), '')
          .trim();
      if (line.isEmpty ||
          line.length > 55 ||
          !_letters.hasMatch(line) ||
          _nonNameLine.hasMatch(line) ||
          _collectorPattern.hasMatch(line) ||
          _promoPattern.hasMatch(line) ||
          RegExp(r'\d{3,}').hasMatch(line)) {
        continue;
      }
      // A stray Latin letter or symbol often comes from the illustration.
      // Keep single-character CJK names such as 뮤, but reject Latin noise.
      if (!RegExp(
            r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',
          ).hasMatch(line) &&
          _letters.allMatches(line).length < 3) {
        continue;
      }
      // Names usually occupy a short line near the top beside the HP badge.
      names.add(line);
      final score = 100 - i * 5 + (_hp.hasMatch(original) ? 20 : 0);
      if (score > bestScore) {
        bestName = line;
        bestScore = score;
      }
    }
    return ScanResult(
      rawText: text,
      cardName: bestName,
      collectorNumber: number,
      nameCandidates: List.unmodifiable(names),
    );
  }
}
