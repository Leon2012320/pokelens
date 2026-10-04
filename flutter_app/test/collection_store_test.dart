import 'package:flutter_test/flutter_test.dart';
import 'package:pokelens/services/catalog_service.dart';
import 'package:pokelens/services/collection_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty without creating fictional holdings', () async {
    final store = CollectionStore();
    await store.load();
    expect(store.entries, isEmpty);
    expect(() => store.entries.clear(), throwsUnsupportedError);
    store.dispose();
  });

  test('persists separate owned copies and removes just one', () async {
    final store = CollectionStore();
    final card = CatalogService.demoCatalog.first;
    await store.add(card, condition: 'Excellent', variant: 'Holo');
    await store.add(card, condition: 'Good', variant: 'Standard');
    expect(store.entries, hasLength(2));
    expect(store.entries.map((entry) => entry.id).toSet(), hasLength(2));
    final reloaded = CollectionStore();
    await reloaded.load();
    expect(reloaded.entries, hasLength(2));
    expect(reloaded.entries.first.condition, 'Good');
    expect(reloaded.entries.last.variant, 'Holo');
    expect(reloaded.entries.last.card.displayNumber, '199/165');
    await reloaded.remove(reloaded.entries.first.id);
    final afterRemove = CollectionStore();
    await afterRemove.load();
    expect(afterRemove.entries, hasLength(1));
    expect(afterRemove.entries.single.condition, 'Excellent');
    store.dispose();
    reloaded.dispose();
    afterRemove.dispose();
  });

  test('serializes concurrent adds without lost copies', () async {
    final store = CollectionStore();
    await Future.wait(
      List.generate(8, (_) => store.add(CatalogService.demoCatalog.first)),
    );
    expect(store.entries, hasLength(8));
    final restored = CollectionStore();
    await restored.load();
    expect(restored.entries, hasLength(8));
    store.dispose();
    restored.dispose();
  });

  test(
    'surfaces corrupted storage and never overwrites it during add',
    () async {
      SharedPreferences.setMockInitialValues({
        CollectionStore.storageKey: '{corrupt',
      });
      final store = CollectionStore();
      await expectLater(store.load(), throwsA(isA<CollectionException>()));
      await expectLater(
        store.add(CatalogService.demoCatalog.first),
        throwsA(isA<CollectionException>()),
      );
      expect(store.entries, isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString(CollectionStore.storageKey), '{corrupt');
      store.dispose();
    },
  );
}
