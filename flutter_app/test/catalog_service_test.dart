import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokelens/models/pokemon_card.dart';
import 'package:pokelens/services/catalog_service.dart';

Map<String, dynamic> cardJson({
  String id = 'sv03.5-199',
  String name = 'Glurak-ex',
  String localId = '199',
  Map<String, dynamic>? market,
}) => {
  'id': id,
  'name': name,
  'localId': localId,
  'image': 'https://assets.tcgdex.net/de/sv/sv03.5/199',
  'set': {
    'name': '151',
    'cardCount': {'official': 165, 'total': 207},
  },
  'variants': {'normal': false, 'holo': true},
  if (market != null) 'pricing': {'cardmarket': market},
};

http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('Photo name matching', () {
    test(
      'keeps printings of an OCR-damaged name and skips digital cards',
      () async {
        var requests = 0;
        final service = CatalogService(
          client: MockClient((request) async {
            requests++;
            expect(request.url.path, '/v2/de/cards');
            return jsonResponse([
              cardJson(),
              cardJson(id: 'sv03.5-6', localId: '6'),
              cardJson(id: 'base1-4', name: 'Glurak'),
              cardJson(id: 'sv03.5-151', name: 'Mew-ex'),
              {
                ...cardJson(id: 'A1-36'),
                'image': 'https://assets.tcgdex.net/de/tcgp/A1/36',
              },
            ]);
          }),
        );
        addTearDown(service.dispose);
        final cards = await service.scanCandidates('Glüurak@eSX');
        expect(cards.map((card) => card.id), [
          'sv03.5-199',
          'sv03.5-6',
          'base1-4',
        ]);
        expect(
          await service.scanCandidates(
            'garbled text',
            alternatives: ['Glüurak@eSX'],
          ),
          hasLength(3),
        );
        expect(requests, 1);
        expect(await service.scanCandidates('zzzzzzzz'), isEmpty);
      },
    );

    test('a failed catalogue load can be retried', () async {
      var requests = 0;
      final service = CatalogService(
        client: MockClient((_) async {
          return ++requests == 1
              ? http.Response('', 503)
              : jsonResponse([cardJson()]);
        }),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.scanCandidates('Glurak-ex'),
        throwsA(isA<CatalogException>()),
      );
      expect(
        (await service.scanCandidates('Glurak-ex')).single.id,
        'sv03.5-199',
      );
    });
  });

  group('Cardmarket parsing', () {
    test('keeps market-standard and foil buckets separate', () {
      final card = PokemonCard.fromJson(
        cardJson(
          market: {
            'trend': 296.62,
            'low': 229,
            'avg7': 334.48,
            'avg30': 377.37,
            'trend-holo': 0,
            'low-holo': null,
            'unit': 'EUR',
            'idProduct': 733794,
            'updated': '2026-09-04T10:05:09.379Z',
          },
        ),
      );
      expect(card.market!.trend, 296.62);
      expect(card.market!.low, 229);
      expect(card.market!.holoTrend, isNull);
      expect(card.market!.holoLow, isNull);
      expect(card.market!.currency, 'EUR');
      expect(card.market!.updated, DateTime.utc(2026, 9, 4, 10, 5, 9, 379));
      expect(card.cardmarketId, 733794);
      expect(card.defaultVariant, 'Holo');
      expect(card.displayNumber, '199/165');
      expect(card.imageUrl, endsWith('/199/high.webp'));
    });

    test('does not fabricate absent or invalid prices', () {
      expect(PokemonCard.fromJson(cardJson()).market, isNull);
      final market = MarketPrice.fromJson({
        'trend': -1,
        'low': 'NaN',
        'avg7': double.infinity,
        'avg30': 'invalid',
        'trend-holo': '12.34',
      });
      expect(market.trend, isNull);
      expect(market.low, isNull);
      expect(market.avg7, isNull);
      expect(market.avg30, isNull);
      expect(market.holoTrend, 12.34);
      expect(market.updated, isNull);
      expect(
        CatalogService.demoCatalog.every((card) => card.market == null),
        isTrue,
      );
    });

    test('round-trips localized cards and complete price snapshots', () {
      final original = PokemonCard.fromJson(
        cardJson(
          market: {
            'trend': 5.2,
            'trend-holo': 6.3,
            'low-holo': 4.1,
            'avg7-holo': 6.1,
            'avg30-holo': 6.4,
            'updated': '2026-09-04T00:00:00Z',
          },
        ),
        language: 'ja',
      );
      final saved =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final restored = PokemonCard.fromJson(saved);
      expect(restored.toJson(), original.toJson());
      expect(restored.language, 'ja');
      expect(restored.market!.holoAvg30, 6.4);
    });

    test('accepts both timestamp units and rejects impossible dates', () {
      final seconds = MarketPrice.fromJson({'updated': 1754354535});
      final milliseconds = MarketPrice.fromJson({'updated': 1754354535000});
      expect(seconds.updated, milliseconds.updated);
      expect(
        MarketPrice.fromJson({'updated': double.infinity}).updated,
        isNull,
      );
      expect(MarketPrice.fromJson({'updated': 1e30}).updated, isNull);
    });
  });

  group('Catalog search', () {
    test('looks up ids in the requested language and caches details', () async {
      var requests = 0;
      final service = CatalogService(
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, '/v2/fr/cards/sv03.5-199');
          return jsonResponse(cardJson(name: 'Dracaufeu-ex'));
        }),
      );
      final cards = await service.search('sv03.5-199', language: 'fr');
      expect(cards.single.name, 'Dracaufeu-ex');
      expect(cards.single.language, 'fr');
      await service.getCard('sv03.5-199', language: 'fr');
      expect(requests, 1);
      service.dispose();
    });

    test('parses number/denominator and rejects substring matches', () async {
      final service = CatalogService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cards')) {
            expect(request.url.queryParameters['localId'], '199');
            expect(
              request.url.queryParameters['set.cardCount.official'],
              '165',
            );
            expect(request.url.queryParameters['name'], isNull);
            return jsonResponse([
              cardJson(),
              cardJson(id: 'other-1199', localId: '1199'),
              cardJson(id: 'promo-SM199', localId: 'SM199'),
            ]);
          }
          expect(request.url.path, '/v2/de/cards/sv03.5-199');
          return jsonResponse(cardJson(market: {'trend': 296.62}));
        }),
      );
      final cards = await service.search('199/165');
      expect(cards.map((card) => card.id), ['sv03.5-199']);
      expect(cards.single.market!.trend, 296.62);
    });

    test('retains the local prefix for Trainer Gallery searches', () async {
      final service = CatalogService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cards')) {
            expect(request.url.queryParameters['localId'], 'TG05');
            expect(
              request.url.queryParameters['set.cardCount.official'],
              isNull,
            );
            return jsonResponse([cardJson(id: 'swsh9-TG05', localId: 'TG05')]);
          }
          return jsonResponse(cardJson(id: 'swsh9-TG05', localId: 'TG05'));
        }),
      );
      expect((await service.search('TG05/TG30')).single.localId, 'TG05');
    });

    test('normalizes leading zeroes on printed collector numbers', () async {
      final service = CatalogService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cards')) {
            expect(request.url.queryParameters['localId'], '1');
            expect(
              request.url.queryParameters['set.cardCount.official'],
              '165',
            );
            return jsonResponse([
              cardJson(id: 'sv03.5-1', localId: '1'),
              cardJson(id: 'sv03.5-10', localId: '10'),
            ]);
          }
          return jsonResponse(cardJson(id: 'sv03.5-1', localId: '1'));
        }),
      );
      expect((await service.search('001/165')).single.id, 'sv03.5-1');
    });

    test(
      'resolves Japanese promo collector notation and preserves its set',
      () async {
        final service = CatalogService(
          client: MockClient((request) async {
            expect(request.url.path, '/v2/ja/cards/SV-P-001');
            return jsonResponse(
              cardJson(id: 'SV-P-001', localId: '001', name: 'ピカチュウ'),
            );
          }),
        );
        final cards = await service.search('001/SV-P', language: 'ja');
        expect(cards.single.id, 'SV-P-001');
        expect(cards.single.displayNumber, '001/SV-P');
        expect(
          (await service.search('SV-P-001', language: 'ja')).single.id,
          'SV-P-001',
        );
      },
    );

    test(
      'sends Unicode names without changing the selected language',
      () async {
        final service = CatalogService(
          client: MockClient((request) async {
            expect(request.url.path, '/v2/ja/cards');
            expect(request.url.queryParameters['name'], 'ピカチュウ');
            return jsonResponse([]);
          }),
        );
        expect(await service.search('ピカチュウ', language: 'ja'), isEmpty);
      },
    );

    test('preserves card briefs when price enrichment fails', () async {
      final service = CatalogService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/cards')) {
            return jsonResponse([cardJson()]);
          }
          return http.Response('unavailable', 503);
        }),
      );
      final cards = await service.search('Glurak');
      expect(cards.single.name, 'Glurak-ex');
      expect(cards.single.market, isNull);
    });

    test('does not show a not-found id as a fabricated card', () async {
      final service = CatalogService(
        client: MockClient((_) async => http.Response('', 404)),
      );
      expect(await service.search('sv03.5-999'), isEmpty);
    });

    test(
      'surfaces readable timeout, network and malformed-response errors',
      () async {
        final timeout = CatalogService(
          client: MockClient((_) => Completer<http.Response>().future),
          requestTimeout: const Duration(milliseconds: 1),
        );
        await expectLater(
          timeout.getCard('base1-1'),
          throwsA(
            isA<CatalogException>().having(
              (error) => error.message,
              'message',
              contains('dauert zu lange'),
            ),
          ),
        );
        final offline = CatalogService(
          client: MockClient((_) async {
            throw http.ClientException('network unreachable');
          }),
        );
        await expectLater(
          offline.search('Pikachu'),
          throwsA(
            isA<CatalogException>().having(
              (error) => error.message,
              'message',
              contains('Internetverbindung'),
            ),
          ),
        );
        final malformed = CatalogService(
          client: MockClient((_) async => http.Response('<html>', 200)),
        );
        await expectLater(
          malformed.getCard('base1-1'),
          throwsA(isA<CatalogException>()),
        );
      },
    );
  });
}
