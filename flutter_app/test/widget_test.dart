import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pokelens/models/pokemon_card.dart';
import 'package:pokelens/services/catalog_service.dart';
import 'package:pokelens/services/collection_store.dart';
import 'package:pokelens/services/scan_service.dart';
import 'package:pokelens/ui/app_shell.dart';
import 'package:pokelens/ui/theme.dart';
import 'package:pokelens/ui/widgets.dart';

class TestCatalog extends CatalogService {
  final queries = <String>[];
  @override
  Future<List<PokemonCard>> featured({String language = 'de'}) async =>
      CatalogService.demoCatalog;
  @override
  Future<List<PokemonCard>> search(
    String query, {
    String language = 'de',
  }) async {
    queries.add(query);
    return [CatalogService.demoCatalog.first];
  }

  @override
  Future<List<PokemonCard>> scanCandidates(
    String name, {
    String language = 'de',
    Iterable<String> alternatives = const [],
  }) async => [CatalogService.demoCatalog.first];
  @override
  Future<PokemonCard> getCard(String id, {String language = 'de'}) async =>
      CatalogService.demoCatalog.firstWhere((card) => card.id == id);
}

class TestPhotoPicker extends ImagePicker {
  TestPhotoPicker(this.photo);
  final XFile? photo;
  ImageSource? source;
  CameraDevice? camera;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    camera = preferredCameraDevice;
    return photo;
  }
}

class TestScanBackend implements ScanBackend {
  TestScanBackend({this.error, this.text = 'Rang 2 Glurak-ex KP 330\n199/165'});
  final ScanException? error;
  final String text;
  Uint8List? received;
  @override
  bool get isSupported => true;
  @override
  Future<String> recognize(
    String imagePath, {
    required String language,
    Uint8List? imageBytes,
    ScanProgress? onProgress,
  }) async {
    received = imageBytes;
    onProgress?.call('Kartentext wird gelesen …');
    if (error != null) throw error!;
    return text;
  }
}

Future<void> loadApp(
  WidgetTester tester,
  Size size, {
  CollectionStore? collection,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: AppShell(catalog: TestCatalog(), collection: collection),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    testWidgets('Dashboard and scanner fit ${size.width} viewport', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadApp(tester, size);
      expect(find.text('Dein nächster Fund wartet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Karte scannen').first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Eine Karte. Ein neuer Fund.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Catalog detail saves an ungraded card into real local store', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final collection = CollectionStore();
    await loadApp(tester, const Size(1440, 1000), collection: collection);
    final card = find.byType(CatalogTile).first;
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Kartendetails'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final save = find.text('Zur Sammlung hinzufügen');
    expect(save, findsOneWidget);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(collection.entries, hasLength(1));
    expect(collection.entries.single.condition, 'Ungeprüft');
    final persisted = (await SharedPreferences.getInstance()).getString(
      CollectionStore.storageKey,
    );
    expect(persisted, contains('sv03.5-199'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final source in [ImageSource.camera, ImageSource.gallery]) {
    testWidgets('Photo from $source reaches OCR and collector search', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      SharedPreferences.setMockInitialValues({});
      final bytes = (await rootBundle.load(
        'assets/cards/sv03.5-199.webp',
      )).buffer.asUint8List();
      final picker = TestPhotoPicker(
        XFile.fromData(bytes, name: 'card.webp', mimeType: 'image/webp'),
      );
      final backend = TestScanBackend();
      final catalog = TestCatalog();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: AppShell(
            catalog: catalog,
            scanner: ScanService(backend: backend),
            imagePicker: picker,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Karte scannen').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          source == ImageSource.camera ? 'Foto aufnehmen' : 'Aus Fotos wählen',
        ),
      );
      await tester.pumpAndSettle();
      expect(picker.source, source);
      expect(picker.camera, CameraDevice.rear);
      expect(backend.received, bytes);
      expect(catalog.queries, ['199/165']);
      expect(find.text('Erkannt: 199/165'), findsOneWidget);
      expect(find.byType(CatalogTile), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Recognition failure explains retry and enables photo controls', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final bytes = (await rootBundle.load(
      'assets/cards/sv03.5-199.webp',
    )).buffer.asUint8List();
    final catalog = TestCatalog();
    final backend = TestScanBackend(
      error: const ScanException(
        ScanErrorCode.noText,
        'Kein Text erkannt. Bitte erneut fotografieren.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(
          catalog: catalog,
          scanner: ScanService(backend: backend),
          imagePicker: TestPhotoPicker(
            XFile.fromData(bytes, name: 'card.webp'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Karte scannen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus Fotos wählen'));
    await tester.pumpAndSettle();
    expect(
      find.text('Kein Text erkannt. Bitte erneut fotografieren.'),
      findsOneWidget,
    );
    expect(catalog.queries, isEmpty);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Foto aufnehmen'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
