import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pokemon_card.dart';

class CollectionException implements Exception {
  const CollectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

@immutable
class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.card,
    required this.condition,
    required this.variant,
    required this.addedAt,
  });

  final String id;
  final PokemonCard card;
  final String condition;
  final String variant;
  final DateTime addedAt;

  factory CollectionEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Keine Exemplar-ID.');
    }
    return CollectionEntry(
      id: id,
      card: PokemonCard.fromJson(
        Map<String, dynamic>.from(json['card'] as Map),
      ),
      condition: json['condition'] as String? ?? 'Ungeprüft',
      variant: json['variant'] as String? ?? 'Standard',
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'card': card.toJson(),
    'condition': condition,
    'variant': variant,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };
}

/// One local record per owned copy; repeated scans never silently deduplicate.
class CollectionStore extends ChangeNotifier {
  CollectionStore();

  static const storageKey = 'pokelens.collection.v1';
  SharedPreferences? _preferences;
  List<CollectionEntry> _entries = const [];
  Future<void> _tail = Future<void>.value();
  bool _loaded = false;
  bool _disposed = false;
  final Random _random = Random();

  List<CollectionEntry> get entries => _entries;

  Future<void> load() => _serialize(_load);

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final preferences = _preferences ??=
          await SharedPreferences.getInstance();
      final saved = preferences.getString(storageKey);
      if (saved != null) {
        final decoded = jsonDecode(saved);
        if (decoded is! List) {
          throw const FormatException('Keine Sammlungsliste.');
        }
        // Parse completely before touching state. Damaged data is not replaced.
        final entries = decoded
            .map(
              (item) => CollectionEntry.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false);
        _entries = List.unmodifiable(entries);
      }
      _loaded = true;
      if (!_disposed) notifyListeners();
    } on Object {
      throw const CollectionException(
        'Deine Sammlung konnte nicht geladen werden. Die gespeicherten Daten wurden nicht verändert.',
      );
    }
  }

  Future<void> add(
    PokemonCard card, {
    String condition = 'Ungeprüft',
    String variant = 'Standard',
  }) => _serialize(() async {
    await _load();
    final now = DateTime.now().toUtc();
    final entry = CollectionEntry(
      id: '${now.microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}',
      card: card,
      condition: condition,
      variant: variant,
      addedAt: now,
    );
    await _persist([entry, ..._entries]);
  });

  Future<void> remove(String entryId) => _serialize(() async {
    await _load();
    if (!_entries.any((entry) => entry.id == entryId)) return;
    await _persist(_entries.where((entry) => entry.id != entryId).toList());
  });

  Future<void> _persist(List<CollectionEntry> next) async {
    try {
      final saved = await _preferences!.setString(
        storageKey,
        jsonEncode(next.map((entry) => entry.toJson()).toList()),
      );
      if (!saved) throw const CollectionException('Speichern fehlgeschlagen.');
      // Publish only after persistence succeeds; a failure never looks saved.
      _entries = List.unmodifiable(next);
      if (!_disposed) notifyListeners();
    } on Object {
      throw const CollectionException(
        'Die Änderung konnte nicht gespeichert werden. Bitte versuche es erneut.',
      );
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    if (_disposed) {
      return Future.error(
        const CollectionException('Die Sammlung wurde geschlossen.'),
      );
    }
    final pending = _tail.then((_) => operation());
    // A failed mutation must not block the next user action.
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
