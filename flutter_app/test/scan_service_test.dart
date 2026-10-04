import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokelens/services/scan_service.dart';

void main() {
  group('OCR search candidates', () {
    test('ignores isolated Latin noise and keeps alternative header names', () {
      final result = ScanService.parseText(
        'ä\nu\nsikarten\nGlüurak@eSX\nRang 2 Glurak-ex KP 330',
      );
      expect(result.nameCandidates, ['sikarten', 'Glüurak@eSX', 'Glurak-ex']);
      expect(ScanService.parseText('ä\nu\n5').suggestedQuery, isEmpty);
    });
    test('removes German stage and HP while preserving the card number', () {
      const text =
          'PHASE 2\nKP 330\nGlurak ex\nEntwickelt sich aus Glutexo\n'
          '199 / 165\n©2023 Pokémon';
      final result = ScanService.parseText(text);
      expect(result.cardName, 'Glurak ex');
      expect(result.collectorNumber, '199/165');
      expect(result.suggestedQuery, '199/165');
      expect(result.rawText, text);
    });

    test('recognizes a name with an inline stage and trailing HP', () {
      final result = ScanService.parseText('BASIC Pikachu 60 HP\n025/165');
      expect(result.cardName, 'Pikachu');
      expect(result.collectorNumber, '025/165');
    });

    test('keeps subset prefixes and leading zeros', () {
      final result = ScanService.parseText('Évoli\nPV 70\nTG11 / TG30');
      expect(result.cardName, 'Évoli');
      expect(result.collectorNumber, 'TG11/TG30');
    });

    test('normalizes Japanese full-width digits and slash', () {
      final result = ScanService.parseText('たね ピカチュウ HP 70\n１７３／１６５');
      expect(result.cardName, 'ピカチュウ');
      expect(result.collectorNumber, '173/165');
    });

    test('preserves Chinese and Korean names', () {
      expect(ScanService.parseText('皮卡丘 HP 60\n025/165').cardName, '皮卡丘');
      expect(ScanService.parseText('기본 피카츄 HP 60\n025/165').cardName, '피카츄');
    });

    test('supports Chinese stage headings and one-character Korean names', () {
      expect(ScanService.parseText('基礎\n皮卡丘 HP 60\n025/165').cardName, '皮卡丘');
      expect(ScanService.parseText('기본 뮤 HP 60\n151/165').cardName, '뮤');
    });

    test('supports Japanese and English promo numbers', () {
      expect(
        ScanService.parseText('ピカチュウ\n001 / SV-P').collectorNumber,
        '001/SV-P',
      );
      expect(
        ScanService.parseText('Pikachu\nSWSH 020').collectorNumber,
        'SWSH020',
      );
    });

    test('ignores HP-only text and copyright years', () {
      final result = ScanService.parseText(
        'HP 120\nKP 90\n2023/2024\n©2024 Pokémon',
      );
      expect(result.cardName, isNull);
      expect(result.collectorNumber, isNull);
      expect(result.suggestedQuery, isEmpty);
    });

    test('can fall back to a name and handles an empty image result', () {
      expect(
        ScanService.parseText('BASIS\nBisasam\nKP 60').suggestedQuery,
        'Bisasam',
      );
      final result = ScanService.parseText(' \n ');
      expect(result.cardName, isNull);
      expect(result.collectorNumber, isNull);
    });

    test('skips trainer headings to extract the actual title', () {
      expect(
        ScanService.parseText(
          'TRAINER\nProfessor\'s Research\n189/202',
        ).cardName,
        'Professor\'s Research',
      );
    });
  });

  test('unsupported platforms return an actionable typed error', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = ScanService();
    expect(service.isSupported, isFalse);
    await expectLater(
      service.recognize('card.jpg'),
      throwsA(
        isA<ScanException>().having(
          (error) => error.code,
          'code',
          ScanErrorCode.unsupportedPlatform,
        ),
      ),
    );
  });

  test(
    'unsupported scripts prompt manual search without native calls',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await expectLater(
        ScanService().recognize('card.jpg', language: 'th'),
        throwsA(
          isA<ScanException>().having(
            (error) => error.code,
            'code',
            ScanErrorCode.unsupportedLanguage,
          ),
        ),
      );
    },
  );
}
