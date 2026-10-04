import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokelens/models/condition_assessment.dart';
import 'package:pokelens/models/pokemon_card.dart';
import 'package:pokelens/services/catalog_service.dart';
import 'package:pokelens/services/collection_store.dart';
import 'package:pokelens/ui/card_detail.dart';
import 'package:pokelens/ui/theme.dart';
import 'package:pokelens/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _card = PokemonCard(
  id: 'sv03.5-199',
  name: 'Glurak ex',
  localId: '199',
  setName: 'Karmesin & Purpur – 151',
  setCardCount: 165,
  language: 'de',
  imageUrl: 'https://assets.tcgdex.net/de/sv/sv03.5/199/high.webp',
  market: MarketPrice(
    trend: 199.95,
    low: 159.25,
    avg7: 189.48,
    avg30: 184.50,
    holoTrend: 204.99,
  ),
);

class _DetailCatalog extends CatalogService {
  @override
  Future<PokemonCard> getCard(String id, {String language = 'de'}) async =>
      _card;
}

Future<CollectionStore> _openDetail(
  WidgetTester tester, {
  required double textScale,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final collection = CollectionStore();
  final catalog = _DetailCatalog();
  addTearDown(collection.dispose);
  addTearDown(catalog.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showCardDetail(
                context,
                card: _card,
                catalog: catalog,
                collection: collection,
              ),
              child: const Text('Karte öffnen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Karte öffnen'));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
  expect(find.text('Kartendetails'), findsOneWidget);
  expect(tester.takeException(), isNull);
  return collection;
}

Future<void> _openAssessment(WidgetTester tester) async {
  final assess = find.widgetWithText(OutlinedButton, 'Zustand einschätzen');
  await tester.ensureVisible(assess);
  await tester.tap(assess);
  await tester.pumpAndSettle();
  expect(find.text('Schau genauer hin.'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Finder get _apply =>
    find.widgetWithText(FilledButton, 'Einschätzung übernehmen');

Future<void> _chooseWear(WidgetTester tester, int field, String choice) async {
  final input = find.byType(DropdownButtonFormField<WearLevel>).at(field);
  await tester.ensureVisible(input);
  await tester.tap(input);
  await tester.pumpAndSettle();
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });

  for (final textScale in [1.0, 1.3]) {
    testWidgets(
      'Phone detail completes manual assessment and saves at $textScale text scale',
      (tester) async {
        final collection = await _openDetail(tester, textScale: textScale);
        final art = tester.widget<Image>(
          find.descendant(
            of: find.byType(CardArt),
            matching: find.byType(Image),
          ),
        );
        expect(art.image, isA<AssetImage>());
        expect(
          (art.image as AssetImage).assetName,
          'assets/cards/sv03.5-199.webp',
        );

        await _openAssessment(tester);
        expect(tester.widget<FilledButton>(_apply).onPressed, isNull);
        expect(find.text('Near Mint'), findsNothing);

        await _chooseWear(tester, 0, 'Leichte Abnutzung');
        expect(tester.widget<FilledButton>(_apply).onPressed, isNull);
        await _chooseWear(tester, 1, 'Keine sichtbare Abnutzung');
        expect(tester.widget<FilledButton>(_apply).onPressed, isNull);
        await _chooseWear(tester, 2, 'Deutliche Abnutzung');
        expect(tester.widget<FilledButton>(_apply).onPressed, isNotNull);

        await tester.ensureVisible(_apply);
        await tester.tap(_apply);
        await tester.pumpAndSettle();
        expect(find.text('Good'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Zur Sammlung hinzufügen'));
        await tester.pumpAndSettle();
        expect(collection.entries, hasLength(1));
        expect(collection.entries.single.condition, 'Good');
        expect(collection.entries.single.variant, 'Marktstandard');
        final preferences = await SharedPreferences.getInstance();
        final saved =
            jsonDecode(preferences.getString(CollectionStore.storageKey)!)
                as List;
        expect((saved.single as Map)['condition'], 'Good');
        expect(find.text('In deiner Sammlung'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('An abandoned assessment does not assign a condition', (
    tester,
  ) async {
    final collection = await _openDetail(tester, textScale: 1.3);
    await _openAssessment(tester);
    await _chooseWear(tester, 0, 'Keine sichtbare Abnutzung');
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Noch nicht eingeschätzt'), findsOneWidget);
    await tester.tap(find.text('Zur Sammlung hinzufügen'));
    await tester.pumpAndSettle();
    expect(collection.entries.single.condition, 'Ungeprüft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
