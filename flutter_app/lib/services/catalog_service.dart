import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pokemon_card.dart';

class CatalogException implements Exception {
  const CatalogException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Public TCGdex REST client. Prices are read only from pricing.cardmarket.
class CatalogService {
  CatalogService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Map<String, ({PokemonCard card, DateTime fetched})> _cache = {};
  final Map<String, Future<List<PokemonCard>>> _scanCatalogs = {};
  bool _disposed = false;

  static const featuredIds = [
    'sv03.5-199',
    'sv03.5-151',
    'swsh7-215',
    'sv04.5-234',
  ];

  /// Discovery metadata only. These are neither holdings nor example prices.
  /// Callers should identify these as a preview if a live request fails.
  static const demoCatalog = <PokemonCard>[
    PokemonCard(
      id: 'sv03.5-199',
      name: 'Glurak-ex',
      localId: '199',
      setName: '151',
      setCardCount: 165,
      defaultVariant: 'Holo',
      imageUrl: 'https://assets.tcgdex.net/de/sv/sv03.5/199/high.webp',
    ),
    PokemonCard(
      id: 'sv03.5-151',
      name: 'Mew-ex',
      localId: '151',
      setName: '151',
      setCardCount: 165,
      defaultVariant: 'Holo',
      imageUrl: 'https://assets.tcgdex.net/de/sv/sv03.5/151/high.webp',
    ),
    PokemonCard(
      id: 'swsh7-215',
      name: 'Nachtara VMAX',
      localId: '215',
      setName: 'Drachenwandel',
      setCardCount: 203,
      defaultVariant: 'Holo',
      imageUrl: 'https://assets.tcgdex.net/de/swsh/swsh7/215/high.webp',
    ),
    PokemonCard(
      id: 'sv04.5-234',
      name: 'Glurak-ex',
      localId: '234',
      setName: 'Paldeas Schicksale',
      setCardCount: 91,
      defaultVariant: 'Holo',
      imageUrl: 'https://assets.tcgdex.net/de/sv/sv04.5/234/high.webp',
    ),
  ];

  Future<List<PokemonCard>> featured({String language = 'de'}) async {
    CatalogException? failure;
    final cards = await Future.wait(
      featuredIds.map((id) async {
        try {
          return await getCard(id, language: language);
        } on CatalogException catch (error) {
          failure ??= error;
          return null;
        }
      }),
    );
    final available = cards.whereType<PokemonCard>().toList(growable: false);
    if (available.isEmpty && failure != null) throw failure!;
    return available;
  }

  /// Searches the selected catalog language, including collector notation
  /// such as 199/165, TG05/TG30, or a TCGdex id such as sv03.5-199.
  Future<List<PokemonCard>> search(
    String query, {
    String language = 'de',
  }) async {
    final text = query.trim();
    if (text.isEmpty) return featured(language: language);
    if (text.length > 160) {
      throw const CatalogException(
        'Bitte verkürze deine Suche auf 160 Zeichen.',
      );
    }

    final promo = RegExp(
      r'^#?(\d{1,3})\s*/\s*([A-Za-z]{1,3}-P)$',
      caseSensitive: false,
    ).firstMatch(text);
    final exactId = promo == null
        ? text
        : '${promo[2]!.toUpperCase()}-${promo[1]!.padLeft(3, '0')}';
    if (promo != null ||
        RegExp(
          r'^[A-Za-z][A-Za-z0-9.-]*-[A-Za-z]*\d+[A-Za-z]*$',
        ).hasMatch(text)) {
      try {
        return [await getCard(exactId, language: language)];
      } on CatalogException catch (error) {
        if (error.statusCode == 404) return [];
        rethrow;
      }
    }

    final collector = RegExp(
      r'(?:^|\s)#?([A-Za-z]{0,5}\d{1,4}[A-Za-z]?)\s*(?:/\s*([A-Za-z]{0,5}\d{1,4}))?(?=\s|$)',
    ).firstMatch(text);
    final localId = collector?.group(1);
    final lookupId = localId == null
        ? null
        : int.tryParse(localId)?.toString() ?? localId;
    final denominator = collector?.group(2);
    final name = collector == null
        ? text
        : text.replaceRange(collector.start, collector.end, '').trim();
    final parameters = <String, String>{
      'pagination:page': '1',
      'pagination:itemsPerPage': '60',
      if (name.isNotEmpty) 'name': name,
      // The deployed API's eq: prefix currently fails for numeric localIds.
      // Query a superset and enforce exact normalized equality below.
      'localId': ?lookupId,
      if (denominator != null && int.tryParse(denominator) != null)
        'set.cardCount.official': int.parse(denominator).toString(),
    };
    final response = await _get(_uri(language, ['cards'], parameters));
    if (response is! List) {
      throw const CatalogException(
        'Der Kartenkatalog hat ungültige Suchdaten geliefert.',
      );
    }
    List<PokemonCard> brief;
    try {
      brief = response
          .map(
            (item) => PokemonCard.fromJson(
              Map<String, dynamic>.from(item as Map),
              language: language,
            ),
          )
          .where((card) {
            // Digital Pokémon TCG Pocket cards cannot be owned or sold physically.
            if (card.imageUrl?.contains('/tcgp/') == true) return false;
            return localId == null || _number(card.localId) == _number(localId);
          })
          .take(30)
          .toList(growable: false);
    } on Object {
      throw const CatalogException(
        'Die Suchergebnisse konnten nicht gelesen werden.',
      );
    }

    // Search responses contain only card briefs. Enrich in small batches so
    // names, set names, reference prices and timestamps stay source-backed.
    final results = <PokemonCard>[];
    for (var start = 0; start < brief.length; start += 6) {
      final batch = brief.skip(start).take(6);
      results.addAll(
        await Future.wait(
          batch.map((card) async {
            try {
              return await getCard(card.id, language: language);
            } on CatalogException {
              // A usable search result remains usable with missing price data.
              return card;
            }
          }),
        ),
      );
    }
    return List.unmodifiable(results);
  }

  /// Names are matched against the real catalogue, including OCR typos. Keep
  /// all printings of the closest name for the subsequent visual comparison.
  Future<List<PokemonCard>> scanCandidates(
    String name, {
    String language = 'de',
    Iterable<String> alternatives = const [],
  }) async {
    final targets = [
      name,
      ...alternatives,
    ].map(_scanName).where((target) => target.isNotEmpty).toSet();
    if (targets.isEmpty) return const [];
    final loading = _scanCatalogs.putIfAbsent(language, () async {
      final data = await _get(_uri(language, ['cards']));
      if (data is! List) {
        throw const CatalogException(
          'Der Kartenkatalog konnte nicht gelesen werden.',
        );
      }
      return data
          .map(
            (entry) => PokemonCard.fromJson(
              Map<String, dynamic>.from(entry as Map),
              language: language,
            ),
          )
          .where(
            (card) =>
                card.imageUrl != null && !card.imageUrl!.contains('/tcgp/'),
          )
          .toList();
    });
    List<PokemonCard> catalog;
    try {
      catalog = await loading;
    } catch (_) {
      _scanCatalogs.remove(language);
      rethrow;
    }
    final names = <String, int>{};
    for (final card in catalog) {
      names.putIfAbsent(card.name, () {
        var score = 4;
        final candidate = _scanName(card.name);
        for (final target in targets) {
          final distance = _editDistance(target, candidate);
          final tolerance = target.length == 1
              ? 0
              : (target.length < 5 ? 1 : 3);
          if (distance <= tolerance && distance < score) {
            score = distance;
          }
        }
        return score;
      });
    }
    final ranked = names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (ranked.isEmpty || ranked.first.value > 3) {
      return const [];
    }
    final best = ranked.first.value;
    final closest = ranked
        .where((entry) => entry.value == best)
        .map((entry) => entry.key)
        .toSet();
    // OCR often loses the small ex/GX/V mark beside the Pokémon name.
    // Include those printings so the photo comparison can distinguish them.
    String family(String value) =>
        _scanName(value).replaceFirst(RegExp(r'(?:vmax|vstar|ex|gx|v)$'), '');
    final families = closest.map(family).toSet();
    return catalog
        .where((card) => families.contains(family(card.name)))
        .take(100)
        .toList();
  }

  Future<PokemonCard> getCard(String id, {String language = 'de'}) async {
    final uri = _uri(language, ['cards', id]);
    final key = '$language/$id';
    final cached = _cache[key];
    if (!_disposed &&
        cached != null &&
        DateTime.now().difference(cached.fetched) <
            const Duration(minutes: 5)) {
      return cached.card;
    }
    final response = await _get(uri);
    try {
      if (response is! Map) throw const FormatException();
      final card = PokemonCard.fromJson(
        Map<String, dynamic>.from(response),
        language: language,
      );
      _cache[key] = (card: card, fetched: DateTime.now());
      return card;
    } on Object {
      throw const CatalogException(
        'Die Kartendaten konnten nicht gelesen werden.',
      );
    }
  }

  Uri _uri(String language, List<String> parts, [Map<String, String>? query]) {
    if (!RegExp(r'^[a-z]{2}(?:-[a-z]{2})?$').hasMatch(language)) {
      throw const CatalogException(
        'Diese Kartensprache wird nicht unterstützt.',
      );
    }
    return Uri(
      scheme: 'https',
      host: 'api.tcgdex.net',
      pathSegments: ['v2', language, ...parts],
      queryParameters: query,
    );
  }

  Future<Object?> _get(Uri uri) async {
    if (_disposed) {
      throw const CatalogException('Der Kartenkatalog wurde geschlossen.');
    }
    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw CatalogException(switch (response.statusCode) {
          404 => 'Diese Karte wurde in der gewählten Sprache nicht gefunden.',
          400 => 'Die Suchanfrage oder Kartensprache wird nicht unterstützt.',
          429 =>
            'Der Kartenkatalog ist gerade ausgelastet. Bitte versuche es gleich erneut.',
          _ =>
            'Der Kartenkatalog ist gerade nicht erreichbar. Bitte versuche es später erneut.',
        }, statusCode: response.statusCode);
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on CatalogException {
      rethrow;
    } on TimeoutException {
      throw const CatalogException(
        'Die Verbindung dauert zu lange. Bitte versuche es erneut.',
      );
    } on FormatException {
      throw const CatalogException(
        'Der Kartenkatalog hat eine ungültige Antwort geliefert.',
      );
    } on Object {
      throw const CatalogException(
        'Keine Verbindung zum Kartenkatalog. Prüfe deine Internetverbindung.',
      );
    }
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    _scanCatalogs.clear();
    if (_ownsClient) _client.close();
  }
}

String _number(String value) =>
    value.toUpperCase().replaceFirst(RegExp(r'(?<=^|[A-Z])0+(?=\d)'), '');

String _scanName(String name) {
  const accents = {
    'ä': 'a',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ö': 'o',
    'ó': 'o',
    'ô': 'o',
    'ü': 'u',
    'ú': 'u',
    'û': 'u',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ç': 'c',
    'ñ': 'n',
    'ß': 'ss',
  };
  var normalized = name.toLowerCase();
  for (final entry in accents.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

int _editDistance(String a, String b) {
  if ((a.length - b.length).abs() > 3) return 4;
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = List.filled(b.length + 1, 0)..[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final substitution = previous[j] + (a[i] == b[j] ? 0 : 1);
      final insertion = current[j] + 1;
      final deletion = previous[j + 1] + 1;
      current[j + 1] = substitution < insertion ? substitution : insertion;
      if (deletion < current[j + 1]) current[j + 1] = deletion;
    }
    previous = current;
  }
  return previous.last;
}
