/// A localized physical card and its unmodified marketplace price snapshot.
class PokemonCard {
  const PokemonCard({
    required this.id,
    required this.name,
    required this.localId,
    required this.setName,
    this.language = 'de',
    this.imageUrl,
    this.market,
    this.setCardCount,
    this.cardmarketId,
    this.defaultVariant = 'Standard',
  });

  final String id;
  final String name;
  final String localId;
  final String setName;
  final String language;
  final String? imageUrl;
  final MarketPrice? market;
  final int? setCardCount;
  final int? cardmarketId;

  /// The printed card finish; this does not select a Cardmarket price bucket.
  /// For example, a holo-only card can have its price in the base trend field.
  final String defaultVariant;

  String get displayNumber {
    final promoSet = RegExp(r'^([A-Z]{1,3}-P)-').firstMatch(id)?.group(1);
    if (promoSet != null) return '$localId/$promoSet';
    return setCardCount == null ? localId : '$localId/$setCardCount';
  }

  factory PokemonCard.fromJson(
    Map<String, dynamic> json, {
    String language = 'de',
  }) {
    final id = _requiredText(json, 'id');
    final set = _object(json['set']);
    final cardCount = _object(set?['cardCount']);
    final pricing = _object(json['pricing']);
    final marketJson =
        _object(pricing?['cardmarket']) ?? _object(json['market']);
    final variants = _object(json['variants']);
    final rawImage = json['imageUrl'] ?? json['image'];
    String? imageUrl;
    if (rawImage is String && rawImage.isNotEmpty) {
      // TCGdex returns an asset base URL, without resolution or extension.
      imageUrl =
          RegExp(
            r'\.(png|jpe?g|webp)(\?.*)?$',
            caseSensitive: false,
          ).hasMatch(rawImage)
          ? rawImage
          : '${rawImage.replaceAll(RegExp(r'/+$'), '')}/high.webp';
    }
    return PokemonCard(
      id: id,
      name: _requiredText(json, 'name'),
      localId: json['localId']?.toString() ?? id.split('-').last,
      setName: (json['setName'] ?? set?['name'] ?? id.split('-').first)
          .toString(),
      language: json['language'] is String
          ? json['language'] as String
          : language,
      imageUrl: imageUrl,
      market: marketJson == null ? null : MarketPrice.fromJson(marketJson),
      setCardCount: _integer(json['setCardCount'] ?? cardCount?['official']),
      cardmarketId: _integer(json['cardmarketId'] ?? marketJson?['idProduct']),
      defaultVariant:
          json['defaultVariant'] as String? ??
          (variants?['holo'] == true && variants?['normal'] != true
              ? 'Holo'
              : 'Standard'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'localId': localId,
    'setName': setName,
    'language': language,
    'imageUrl': imageUrl,
    'market': market?.toJson(),
    'setCardCount': setCardCount,
    'cardmarketId': cardmarketId,
    'defaultVariant': defaultVariant,
  };
}

/// Cardmarket fields as delivered by TCGdex. Missing prices stay missing.
/// These are market reference prices, not condition/language-specific offers.
class MarketPrice {
  const MarketPrice({
    this.trend,
    this.low,
    this.avg7,
    this.avg30,
    this.holoTrend,
    this.holoLow,
    this.holoAvg7,
    this.holoAvg30,
    this.updated,
    this.currency = 'EUR',
  });

  final double? trend;
  final double? low;
  final double? avg7;
  final double? avg30;
  final double? holoTrend;
  final double? holoLow;
  final double? holoAvg7;
  final double? holoAvg30;
  final DateTime? updated;
  final String currency;

  factory MarketPrice.fromJson(Map<String, dynamic> json) => MarketPrice(
    trend: _price(json['trend']),
    low: _price(json['low']),
    avg7: _price(json['avg7']),
    avg30: _price(json['avg30']),
    holoTrend: _price(json['trend-holo']),
    holoLow: _price(json['low-holo']),
    holoAvg7: _price(json['avg7-holo']),
    holoAvg30: _price(json['avg30-holo']),
    updated: _date(json['updated']),
    currency: (json['unit'] ?? json['currency'] ?? 'EUR').toString(),
  );

  Map<String, dynamic> toJson() => {
    'trend': trend,
    'low': low,
    'avg7': avg7,
    'avg30': avg30,
    'trend-holo': holoTrend,
    'low-holo': holoLow,
    'avg7-holo': holoAvg7,
    'avg30-holo': holoAvg30,
    'updated': updated?.toUtc().toIso8601String(),
    'unit': currency,
  };
}

Map<String, dynamic>? _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

String _requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Kartendaten enthalten kein gültiges Feld $key.');
  }
  return value;
}

int? _integer(Object? value) => value is int
    ? value
    : value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '');

double? _price(Object? value) {
  final price = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  // The feed uses zero for unavailable foil variants. Never display that as
  // a free card, and never substitute another marketplace or finish.
  return price != null && price.isFinite && price > 0 ? price : null;
}

DateTime? _date(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  if (value is num && value.isFinite) {
    final milliseconds = value < 100000000000 ? value * 1000 : value;
    if (milliseconds.abs() > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds.toInt(),
      isUtc: true,
    );
  }
  return null;
}
