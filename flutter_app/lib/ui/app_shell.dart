import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pokemon_card.dart';
import '../services/catalog_service.dart';
import '../services/collection_store.dart';
import '../services/scan_service.dart';
import 'card_detail.dart';
import 'theme.dart';
import 'widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.catalog,
    this.collection,
    this.scanner,
    this.imagePicker,
  });
  final CatalogService? catalog;
  final CollectionStore? collection;
  final ScanService? scanner;
  final ImagePicker? imagePicker;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final CatalogService _catalog;
  late final CollectionStore _collection;
  late final ScanService _scanner;
  late final ImagePicker _imagePicker;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<PokemonCard> _featured = CatalogService.demoCatalog;
  List<PokemonCard> _results = [];
  String _language = 'de';
  String? _catalogError, _searchError, _scanMessage, _storageError;
  bool _fetching = true,
      _searching = false,
      _searched = false,
      _scanning = false;
  Uint8List? _front, _back;
  ScanResult? _recognized;
  int _page = 0, _request = 0, _featuredRequest = 0;
  String _collectionFilter = 'Alle Karten';

  static const _titles = [
    'Übersicht',
    'Karte scannen',
    'Meine Sammlung',
    'Karten entdecken',
    'Einstellungen',
  ];
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.document_scanner_outlined,
    Icons.layers_outlined,
    Icons.explore_outlined,
    Icons.tune_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog ?? CatalogService();
    _collection = widget.collection ?? CollectionStore();
    _scanner = widget.scanner ?? ScanService();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _collection.addListener(_collectionChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('pokelens_language');
      if (saved != null && cardLanguages.containsKey(saved) && mounted) {
        setState(() => _language = saved);
      }
      await _collection.load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _storageError =
              'Deine gespeicherten Daten konnten nicht geladen werden. Bitte starte die App erneut.',
        );
      }
    }
    if (mounted) await _loadFeatured();
  }

  void _collectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFeatured() async {
    final request = ++_featuredRequest;
    setState(() {
      _fetching = true;
      _catalogError = null;
    });
    try {
      final cards = await _catalog.featured(language: _language);
      if (mounted && request == _featuredRequest) {
        setState(() => _featured = cards);
      }
    } catch (_) {
      if (mounted && request == _featuredRequest) {
        setState(() {
          _featured = CatalogService.demoCatalog;
          _catalogError =
              'Preise gerade nicht erreichbar. Du siehst eine Kartenauswahl ohne Livepreise.';
        });
      }
    } finally {
      if (mounted && request == _featuredRequest) {
        setState(() => _fetching = false);
      }
    }
  }

  Future<void> _setLanguage(String language) async {
    setState(() {
      _language = language;
      _request++;
      _searching = false;
      _results = [];
      _searched = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pokelens_language', language);
    } catch (_) {
      _toast('Die Sprache konnte nicht gespeichert werden.');
    }
    if (!mounted) return;
    _loadFeatured();
    if (_search.text.trim().isNotEmpty) _runSearch();
  }

  void _navigate(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _runSearch([String? query]) async {
    if (query != null) {
      _search.text = query;
    }
    final value = _search.text.trim();
    if (value.isEmpty) return;
    final request = ++_request;
    setState(() {
      _searching = true;
      _searched = true;
      _searchError = null;
    });
    try {
      final cards = await _catalog.search(value, language: _language);
      if (mounted && request == _request) setState(() => _results = cards);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _results = [];
          _searchError = error is CatalogException
              ? error.message
              : 'Die Suche ist gerade nicht erreichbar. Versuche es noch einmal.';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _searching = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source, {bool back = false}) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanMessage = null;
    });
    try {
      final photo = await _imagePicker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 2400,
        maxHeight: 3200,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (back) {
          _back = bytes;
        } else {
          _front = bytes;
          _back = null;
          _recognized = null;
        }
      });
      if (back) return;
      setState(() {
        _results = [];
        _searched = false;
        _searchError = null;
      });
      final result = await _scanner.recognize(
        photo.path,
        language: _language,
        imageBytes: bytes,
        onProgress: (message) {
          if (mounted) setState(() => _scanMessage = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _recognized = result;
        _scanMessage =
            'Text erkannt. Prüfe Bild, Set und Kartennummer, bevor du einen Treffer auswählst.';
      });
      if (result.collectorNumber != null) {
        await _runSearch(result.collectorNumber);
      }
      if (mounted &&
          (result.collectorNumber == null ||
              (_results.isEmpty && _searchError == null)) &&
          result.cardName != null) {
        final request = ++_request;
        _search.text = result.cardName!;
        setState(() {
          _searching = true;
          _searched = true;
          _scanMessage = 'Passende Karten werden mit deinem Foto verglichen …';
        });
        try {
          final candidates = await _catalog.scanCandidates(
            result.cardName!,
            language: _language,
            alternatives: result.nameCandidates,
          );
          final ranked = await _scanner.rankCandidates(bytes, candidates);
          final cards = await Future.wait(
            ranked.take(8).map((card) async {
              try {
                return await _catalog.getCard(card.id, language: _language);
              } on CatalogException {
                return card;
              }
            }),
          );
          if (mounted && request == _request) {
            setState(() {
              _results = cards;
              if (cards.isNotEmpty) _search.text = cards.first.name;
              _searchError = null;
              _scanMessage = cards.isEmpty
                  ? 'Text gelesen, aber keine passende Karte gefunden. Prüfe die Sprache und suche mit der Nummer unten auf der Karte.'
                  : 'Foto erkannt. Die ähnlichsten Karten stehen zuerst. Bestätige Bild, Set und Nummer.';
            });
          }
        } on CatalogException catch (error) {
          if (mounted && request == _request) {
            setState(() {
              _results = [];
              _searchError = error.message;
            });
          }
        } finally {
          if (mounted && request == _request) {
            setState(() => _searching = false);
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _scanMessage = error is ScanException
              ? error.message
              : 'Das Foto konnte nicht geöffnet werden. Prüfe den Kamera- oder Fotozugriff in den Geräteeinstellungen.',
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _detail(PokemonCard card) => showCardDetail(
    context,
    card: card,
    catalog: _catalog,
    collection: _collection,
  );

  @override
  void dispose() {
    _request++;
    _featuredRequest++;
    _collection.removeListener(_collectionChanged);
    _collection.dispose();
    _catalog.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      final tablet = constraints.maxWidth >= 700;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (desktop) _sidebar(),
              Expanded(
                child: Column(
                  children: [
                    _header(desktop, tablet),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: EdgeInsets.all(tablet ? 30 : 20),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1300),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_storageError != null) ...[
                                  _notice(
                                    _storageError!,
                                    Icons.cloud_off_outlined,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                switch (_page) {
                                  0 => _home(),
                                  1 => _scanPage(),
                                  2 => _collectionPage(),
                                  3 => _discoverPage(),
                                  _ => _settingsPage(),
                                },
                                const SizedBox(height: 32),
                                _footer(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: _page > 3 ? 0 : _page,
                onDestinationSelected: _navigate,
                backgroundColor: Colors.white,
                indicatorColor: palePurple,
                height: 74,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded, color: accent),
                    label: 'Übersicht',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.document_scanner_outlined),
                    selectedIcon: Icon(Icons.document_scanner, color: accent),
                    label: 'Scannen',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.layers_outlined),
                    selectedIcon: Icon(Icons.layers, color: accent),
                    label: 'Sammlung',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore, color: accent),
                    label: 'Entdecken',
                  ),
                ],
              ),
      );
    },
  );

  Widget _sidebar() => Container(
    width: 220,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(26, 31, 20, 40),
          child: Row(
            children: [
              LensLogo(),
              SizedBox(width: 11),
              Text(
                'pokélens',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 29, bottom: 13),
          child: Text(
            'DEIN SAMMLERSPACE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: muted,
            ),
          ),
        ),
        for (int i = 0; i < 4; i++) _navItem(i),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(19),
          child: Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5FC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: accent,
                  size: 23,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kleine Karte.\nGroße Geschichte.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Entdecke, was deine\nSammlung besonders macht.',
                  style: TextStyle(fontSize: 10, color: muted, height: 1.8),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _navigate(1),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Text(
                          'Jetzt scannen',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 14, color: accent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _navItem(4),
        Padding(
          padding: const EdgeInsets.fromLTRB(27, 12, 22, 24),
          child: InkWell(
            onTap: _showHelp,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.help_outline_rounded, size: 20, color: muted),
                  SizedBox(width: 12),
                  Text(
                    'Hilfe & Tipps',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 25, vertical: 23),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: palePurple,
                child: Text(
                  'DU',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dein Sammlerspace',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Lokal auf deinem Gerät',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _navItem(int index) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    child: Material(
      color: _page == index ? palePurple : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _navigate(index),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                _icons[index],
                color: _page == index ? accent : muted,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _titles[index],
                  style: TextStyle(
                    fontWeight: _page == index
                        ? FontWeight.w800
                        : FontWeight.w600,
                    fontSize: 12,
                    color: _page == index ? accent : muted,
                  ),
                ),
              ),
              if (index == 2 && _collection.entries.isNotEmpty)
                Text(
                  '${_collection.entries.length}',
                  style: const TextStyle(fontSize: 10, color: accent),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header(bool desktop, bool tablet) => Container(
    height: 84,
    padding: EdgeInsets.symmetric(horizontal: tablet ? 32 : 20),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (!desktop) ...[const LensLogo(size: 31), const SizedBox(width: 10)],
        Text(
          desktop ? _titles[_page] : 'pokélens',
          style: TextStyle(
            fontSize: desktop ? 17 : 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
        const Spacer(),
        if (tablet)
          SizedBox(
            width: 260,
            height: 42,
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 11),
              onSubmitted: (_) {
                _navigate(3);
                _runSearch();
              },
              decoration: InputDecoration(
                hintText: 'Karten, Sets oder Nummer suchen',
                prefixIcon: const Icon(Icons.search, size: 18, color: muted),
                fillColor: canvas,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                suffixIcon: IconButton(
                  tooltip: 'Suchen',
                  icon: const Icon(Icons.arrow_forward, size: 16, color: muted),
                  onPressed: () {
                    _navigate(3);
                    _runSearch();
                  },
                ),
              ),
            ),
          ),
        SizedBox(width: tablet ? 20 : 10),
        _languageMenu(compact: true),
        if (!desktop) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: () => _navigate(4),
            icon: const Icon(Icons.tune_rounded, size: 21, color: muted),
          ),
        ],
        if (desktop) ...[
          const SizedBox(width: 18),
          Container(width: 1, height: 25, color: line),
          const SizedBox(width: 20),
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFF5EDE3),
            child: Icon(
              Icons.person_outline_rounded,
              color: Color(0xFFB29373),
              size: 19,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _languageMenu({bool compact = false}) => PopupMenuButton<String>(
    tooltip: 'Kartensprache auswählen',
    initialValue: _language,
    onSelected: _setLanguage,
    itemBuilder: (_) => cardLanguages.entries
        .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 14, vertical: 10),
      decoration: BoxDecoration(
        color: compact ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: compact ? null : Border.all(color: line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, color: muted, size: 17),
          const SizedBox(width: 8),
          Text(
            compact ? _language.toUpperCase() : cardLanguages[_language]!,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 5),
          const Icon(Icons.keyboard_arrow_down_rounded, color: muted, size: 16),
        ],
      ),
    ),
  );

  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dein nächster Fund wartet.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Scannen. Entdecken. Mit Freude sammeln.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 600)
            const Pill('FÜR SAMMLER', icon: Icons.favorite_border_rounded),
        ],
      ),
      const SizedBox(height: 25),
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: _hero()),
                    const SizedBox(width: 22),
                    Expanded(flex: 3, child: _howItWorks()),
                  ],
                )
              : _hero();
        },
      ),
      const SizedBox(height: 22),
      _stats(),
      const SizedBox(height: 30),
      _section(
        'Besondere Karten entdecken',
        'Ein bisschen Inspiration für deine nächste Lieblingskarte.',
        action: 'Alle Karten',
        onTap: () => _navigate(3),
      ),
      const SizedBox(height: 17),
      if (_catalogError != null) ...[
        _notice(_catalogError!, Icons.wifi_off_rounded, onRetry: _loadFeatured),
        const SizedBox(height: 14),
      ],
      _cardGrid(_featured),
      const SizedBox(height: 16),
      Row(
        children: [
          Icon(
            _fetching ? Icons.sync : Icons.info_outline,
            size: 13,
            color: muted,
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Markttrend in EUR · Cardmarket via TCGdex · Sprache und Zustand können den Verkaufspreis verändern.',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ),
        ],
      ),
      const SizedBox(height: 28),
      _collectionStrip(),
    ],
  );

  Widget _hero() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 530;
      if (compact) return _mobileHero();
      return Container(
        width: double.infinity,
        height: compact ? 480 : 330,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFF0ECFB),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -65,
              top: -40,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .6),
                    width: 1,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -20,
              top: 7,
              child: Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .7),
                    width: 1,
                  ),
                ),
              ),
            ),
            Positioned(
              right: compact ? 20 : 22,
              top: compact ? 275 : 25,
              child: Transform.rotate(
                angle: .13,
                child: Container(
                  width: compact ? 122 : 167,
                  height: compact ? 171 : 234,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C5192).withValues(alpha: .24),
                        blurRadius: 24,
                        offset: const Offset(5, 13),
                      ),
                    ],
                  ),
                  child: CardArt(card: CatalogService.demoCatalog.first),
                ),
              ),
            ),
            Positioned(
              right: compact ? 105 : 75,
              bottom: compact ? 27 : 23,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: .1),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: accent),
                    SizedBox(width: 7),
                    Text(
                      'Jede Karte hat eine Geschichte.',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 25 : 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEIN POKÉMON-KARTENSCANNER',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Deine Karten.\nIhr wahrer Wert.',
                    style: TextStyle(
                      fontSize: compact ? 33 : 35,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      height: 1.16,
                    ),
                  ),
                  const SizedBox(height: 13),
                  SizedBox(
                    width: compact ? 185 : 270,
                    child: Text(
                      'Entdecke deine Pokémon-Karten,\nihren Marktpreis und ihren Zustand.',
                      style: TextStyle(
                        fontSize: compact ? 11 : 11,
                        color: const Color(0xFF817990),
                        height: 1.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 21),
                  FilledButton.icon(
                    onPressed: () => _navigate(1),
                    icon: const Icon(Icons.document_scanner_outlined, size: 17),
                    label: const Text('Karte scannen'),
                  ),
                  const SizedBox(height: 12),
                  if (!compact)
                    const Row(
                      children: [
                        Icon(Icons.language, size: 12, color: muted),
                        SizedBox(width: 6),
                        Text(
                          'Mehrsprachig',
                          style: TextStyle(fontSize: 9, color: muted),
                        ),
                        SizedBox(width: 15),
                        Icon(Icons.lock_outline, size: 12, color: muted),
                        SizedBox(width: 6),
                        Text(
                          'Fotos bleiben bei dir',
                          style: TextStyle(fontSize: 9, color: muted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Positioned(
              right: compact ? 17 : 20,
              top: compact ? 265 : 18,
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFFAF9CDA),
                size: 20,
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _mobileHero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      color: const Color(0xFFF0ECFB),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DEIN POKÉMON-KARTENSCANNER',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            color: accent,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 17),
        const Text(
          'Deine Karten.\nIhr wahrer Wert.',
          style: TextStyle(
            fontSize: 33,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'Entdecke deine Pokémon-Karten, ihren Marktpreis und ihren Zustand.',
          style: TextStyle(fontSize: 12, color: Color(0xFF817990), height: 1.8),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _navigate(1),
          icon: const Icon(Icons.document_scanner_outlined, size: 17),
          label: const Text('Karte scannen'),
        ),
        const SizedBox(height: 23),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 22, color: accent),
                  SizedBox(height: 12),
                  Text(
                    'Jede Karte hat\neine Geschichte.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF817990),
                      height: 1.8,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Mehrsprachig.\nFotos bleiben bei dir.',
                    style: TextStyle(fontSize: 10, color: muted, height: 1.8),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Transform.rotate(
              angle: .10,
              child: SizedBox(
                width: 115,
                height: 160,
                child: CardArt(card: CatalogService.demoCatalog.first),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _howItWorks() => SizedBox(
    height: 330,
    child: Surface(
      padding: const EdgeInsets.all(21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vom Fund zum Favoriten',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 23),
          _step(
            '01',
            'Karte scannen',
            'Foto aufnehmen oder hochladen.',
            Icons.document_scanner_outlined,
          ),
          const SizedBox(height: 19),
          _step(
            '02',
            'Wert entdecken',
            'Karte bestätigen, Marktpreis sehen.',
            Icons.insights_rounded,
          ),
          const SizedBox(height: 19),
          _step(
            '03',
            'Sammlung erweitern',
            'Zustand prüfen und Karte behalten.',
            Icons.layers_outlined,
          ),
          const Spacer(),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 14, color: green),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Ohne Konto. Einfach loslegen.',
                  style: TextStyle(fontSize: 9, color: muted),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _step(
    String number,
    String title,
    String subtitle,
    IconData icon,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: canvas,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: accent, size: 17),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 9, color: muted, height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _stats() {
    final entries = _collection.entries;
    final priced = entries.where((e) => _entryPrice(e) != null).toList();
    final total = priced.fold(0.0, (sum, e) => sum + _entryPrice(e)!);
    final langs = entries.map((e) => e.card.language).toSet().length;
    final items = [
      _stat(
        Icons.layers_outlined,
        'Deine Sammlung',
        '${entries.length}',
        'Karten voller Möglichkeiten',
        palePurple,
        accent,
      ),
      _stat(
        Icons.account_balance_wallet_outlined,
        'Gespeicherter Marktwert',
        entries.isEmpty
            ? euro(0)
            : priced.isEmpty
            ? '–'
            : euro(total),
        '${priced.length} von ${entries.length} Karten mit Preis',
        const Color(0xFFEAF3EF),
        green,
      ),
      _stat(
        Icons.language,
        'Sprachen in deiner Sammlung',
        '$langs',
        'Eine Leidenschaft. Viele Sprachen.',
        const Color(0xFFF9F1E7),
        const Color(0xFFB28C58),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 580
          ? Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  items[i],
                ],
              ],
            )
          : Row(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: items[i]),
                ],
              ],
            ),
    );
  }

  double? _entryPrice(CollectionEntry entry) => entry.variant == 'Holo'
      ? entry.card.market?.holoTrend
      : entry.card.market?.trend;

  Widget _stat(
    IconData icon,
    String title,
    String value,
    String description,
    Color background,
    Color color,
  ) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 9),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ],
    ),
  );

  Widget _section(
    String title,
    String subtitle, {
    String? action,
    VoidCallback? onTap,
  }) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: muted)),
          ],
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                action,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 7),
              const Icon(Icons.arrow_forward, size: 14),
            ],
          ),
        ),
    ],
  );

  Widget _cardGrid(List<PokemonCard> cards) => LayoutBuilder(
    builder: (context, c) {
      final count = c.maxWidth >= 680
          ? 4
          : c.maxWidth >= 480
          ? 3
          : 2;
      final width = (c.maxWidth - (count - 1) * 16) / count;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: width * 1.12 + 116,
        ),
        itemBuilder: (_, i) => CatalogTile(
          card: cards[i],
          index: i,
          onTap: () => _detail(cards[i]),
        ),
      );
    },
  );

  Widget _collectionStrip() => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 21),
    child: Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: palePurple,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.bookmarks_outlined, color: accent, size: 21),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _collection.entries.isEmpty
                    ? 'Deine Sammlung beginnt mit einer Karte.'
                    : 'Deine Lieblingskarten. Immer dabei.',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _collection.entries.isEmpty
                    ? 'Scanne deinen ersten Fund und mach ihn zum Teil deiner Geschichte.'
                    : '${_collection.entries.length} Karten sind auf diesem Gerät gespeichert.',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Sammlung öffnen',
          onPressed: () => _navigate(2),
          icon: const Icon(Icons.arrow_forward, color: accent, size: 20),
        ),
      ],
    ),
  );

  Widget _scanPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Eine Karte. Ein neuer Fund.',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      const Text(
        'Lege deine Karte auf einen ruhigen Hintergrund und sorge für gleichmäßiges Licht.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, c) {
          final preview = _photoPanel();
          final actions = _scanActions();
          return c.maxWidth >= 730
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: preview),
                    const SizedBox(width: 25),
                    Expanded(flex: 4, child: actions),
                  ],
                )
              : Column(
                  children: [preview, const SizedBox(height: 20), actions],
                );
        },
      ),
      if (_scanMessage != null) ...[
        const SizedBox(height: 20),
        _notice(_scanMessage!, Icons.info_outline),
      ],
      if (_recognized != null) ...[
        const SizedBox(height: 12),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                _recognized!.collectorNumber != null
                    ? 'Erkannt: ${_recognized!.collectorNumber}'
                    : 'Erkannten Kartentext ansehen',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              subtitle: const Text(
                'Erkannten Text ansehen und bei Bedarf die Suche korrigieren.',
                style: TextStyle(fontSize: 10, color: muted),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    _recognized!.rawText,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 28),
      _searchBox(),
      if (_searched) ...[const SizedBox(height: 24), _searchResults()],
    ],
  );

  Widget _photoPanel() => Container(
    height: 420,
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      color: const Color(0xFF292736),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Icon(Icons.crop_free, color: Color(0xFFBDB0ED), size: 16),
            const SizedBox(width: 8),
            const Text(
              'VORDERSEITE',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
                color: Color(0xFFD1C9E6),
              ),
            ),
            const Spacer(),
            if (_front != null)
              TextButton(
                onPressed: _scanning
                    ? null
                    : () => setState(() {
                        _front = null;
                        _back = null;
                        _scanMessage = null;
                        _recognized = null;
                        _results = [];
                        _searched = false;
                      }),
                child: const Text(
                  'Zurücksetzen',
                  style: TextStyle(color: Color(0xFFD1C9E6), fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: .72,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: const Color(0xFFA08ADF),
                    width: 1.5,
                  ),
                ),
                child: _front != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_front!, fit: BoxFit.contain),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF433C59), Color(0xFF332F43)],
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.style_outlined,
                              color: Color(0xFFA79AC5),
                              size: 56,
                            ),
                            SizedBox(height: 18),
                            Text(
                              'Platz für deinen\nnächsten Fund',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFFC2B8D6),
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _front != null
                  ? Icons.check_circle_outline
                  : Icons.light_mode_outlined,
              color: const Color(0xFFBCB1D1),
              size: 13,
            ),
            const SizedBox(width: 7),
            Text(
              _front != null
                  ? 'Dein Foto bleibt auf diesem Gerät'
                  : 'Alle vier Ecken sichtbar · ohne Hülle',
              style: const TextStyle(fontSize: 10, color: Color(0xFFBCB1D1)),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _scanActions() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Pill('SCHRITT 01', icon: Icons.document_scanner_outlined),
        const SizedBox(height: 17),
        const Text(
          'Zeig uns deine Karte.',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Fotografiere die ganze Vorderseite. Name und Kartennummer sollten scharf und gut lesbar sein.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        const SizedBox(height: 21),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _scanning ? null : () => _pickPhoto(ImageSource.camera),
            icon: _scanning
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(
              _scanning ? 'Foto wird verarbeitet …' : 'Foto aufnehmen',
            ),
          ),
        ),
        ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scanning
                  ? null
                  : () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Aus Fotos wählen'),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Sprache der Karte',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
            _languageMenu(),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          kIsWeb
              ? 'Die Fotoerkennung läuft auf deinem Gerät. Beim ersten Scan werden Sprachdaten geladen. Auf Handy und iPad öffnet „Foto aufnehmen“ die Kamera, sofern der Browser dies unterstützt.'
              : 'Die Texterkennung schlägt passende Karten vor. Bitte bestätige die genaue Ausgabe selbst.',
          style: const TextStyle(fontSize: 10, color: muted, height: 1.8),
        ),
        if (_front != null) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _scanning
                ? null
                : () => _pickPhoto(ImageSource.gallery, back: true),
            icon: Icon(
              _back == null ? Icons.flip_to_back : Icons.check_circle_outline,
              size: 17,
            ),
            label: Text(
              _back == null ? 'Rückseite ergänzen' : 'Rückseite ersetzen',
            ),
          ),
          if (_back != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                height: 150,
                child: Image.memory(_back!, fit: BoxFit.contain),
              ),
            ),
        ],
      ],
    ),
  );

  Widget _searchBox() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _search,
          onSubmitted: (_) => _runSearch(),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Name oder Kartennummer, z. B. 199/165',
            prefixIcon: Icon(Icons.search, color: muted, size: 21),
          ),
        ),
      ),
      const SizedBox(width: 10),
      FilledButton(
        onPressed: _searching ? null : () => _runSearch(),
        child: const Text('Suchen'),
      ),
    ],
  );

  Widget _discoverPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Finde deine nächste Lieblingskarte.',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 7),
      const Text(
        'Durchstöbere den Katalog und entdecke aktuelle Cardmarket-Marktpreise.',
        style: TextStyle(fontSize: 12, color: muted),
      ),
      const SizedBox(height: 25),
      _searchBox(),
      const SizedBox(height: 15),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in [
            'Pikachu',
            _language == 'de' ? 'Glurak' : 'Charizard',
            'Mew',
            '199/165',
          ])
            ActionChip(
              label: Text(name, style: const TextStyle(fontSize: 11)),
              onPressed: () => _runSearch(name),
              side: const BorderSide(color: line),
              backgroundColor: Colors.white,
            ),
        ],
      ),
      const SizedBox(height: 26),
      if (_searched)
        _searchResults()
      else ...[
        _section(
          'Für deine Wunschliste',
          'Ausgewählte Karten aus dem Pokémon-Universum.',
        ),
        const SizedBox(height: 18),
        if (_catalogError != null) ...[
          _notice(_catalogError!, Icons.wifi_off, onRetry: _loadFeatured),
          const SizedBox(height: 15),
        ],
        _cardGrid(_featured),
      ],
    ],
  );

  Widget _searchResults() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(60),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 20),
              Text(
                'Wir durchsuchen den Kartenkatalog …',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      );
    }
    if (_searchError != null) {
      return _notice(
        _searchError!,
        Icons.wifi_off_rounded,
        onRetry: () => _runSearch(),
      );
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Noch kein passender Fund.',
        description:
            'Prüfe die Kartensprache oder suche nach der Nummer unten auf der Karte. Der Katalog ist je nach Sprache unterschiedlich vollständig.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          '${_results.length} passende Karten',
          'Vergleiche Bild, Set und Nummer. Tippe auf eine Karte für Preis und Zustand.',
        ),
        const SizedBox(height: 18),
        _cardGrid(_results),
      ],
    );
  }

  Widget _collectionPage() {
    final entries = _collection.entries
        .where(
          (e) => _collectionFilter != 'Ungeprüft' || e.condition == 'Ungeprüft',
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          'Deine Karten. Deine Geschichte.',
          'Deine Sammlung wird lokal auf diesem Gerät gespeichert.',
          action: 'Karte hinzufügen',
          onTap: () => _navigate(1),
        ),
        const SizedBox(height: 24),
        _stats(),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          children: [
            for (final filter in ['Alle Karten', 'Ungeprüft'])
              ChoiceChip(
                label: Text(filter, style: const TextStyle(fontSize: 11)),
                selected: _collectionFilter == filter,
                onSelected: (_) => setState(() => _collectionFilter = filter),
                selectedColor: palePurple,
                side: const BorderSide(color: line),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (entries.isEmpty)
          Surface(
            child: EmptyState(
              icon: Icons.layers_outlined,
              title:
                  _collectionFilter == 'Ungeprüft' &&
                      _collection.entries.isNotEmpty
                  ? 'Alles geprüft.'
                  : 'Platz für deine Lieblingskarten.',
              description: _collection.entries.isEmpty
                  ? 'Scanne deine erste Karte oder finde sie im Katalog. Preis und Zustand begleiten sie in deine Sammlung.'
                  : 'In diesem Filter gibt es keine Karten.',
              action: FilledButton.icon(
                onPressed: () => _navigate(1),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Erste Karte hinzufügen'),
              ),
            ),
          )
        else ...[
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _detail(entry.card),
                      child: SizedBox(
                        width: 55,
                        height: 76,
                        child: CardArt(card: entry.card),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () => _detail(entry.card),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.card.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${entry.card.setName} · ${entry.card.displayNumber} · ${entry.card.language.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Pill(entry.condition),
                                Pill(
                                  entry.variant,
                                  color: muted,
                                  background: canvas,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      euro(_entryPrice(entry)),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Karte entfernen',
                      onPressed: () async {
                        try {
                          await _collection.remove(entry.id);
                          _toast('Karte aus deiner Sammlung entfernt.');
                        } catch (_) {
                          _toast('Die Karte konnte nicht entfernt werden.');
                        }
                      },
                      icon: const Icon(Icons.close, size: 17, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Gespeicherte Marktpreise vom jeweiligen Abrufdatum. Der Gesamtwert ist ein Referenzwert ohne Zustands- oder Sprachabschläge.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ],
    );
  }

  Widget _settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Dein Sammlerspace, deine Regeln.',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 25),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kartensprache',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Wähle die Sprache deiner Karte für die Suche und Texterkennung.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            _languageMenu(),
            const SizedBox(height: 20),
            const Text(
              'Lateinische, japanische, chinesische und koreanische Schrift werden mobil erkannt. Für weitere Schriften nutze die Kartennummer. Verfügbare Karten hängen vom Sprachkatalog ab.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: accent, size: 20),
                SizedBox(width: 10),
                Text(
                  'Deine Sammlung bleibt bei dir.',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Kein Konto und kein Foto-Upload an einen Server. Die Texterkennung verarbeitet Fotos auf deinem Gerät. Im Browser werden beim ersten Scan Sprachmodelle heruntergeladen. Zur Kartensuche werden Suchtext und Kartensprache an TCGdex übertragen; Kartenbilder werden von TCGdex geladen.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            SizedBox(height: 12),
            Text(
              'Die Sammlung wird im App-Speicher gesichert. Beim Löschen der App oder der Browserdaten kann sie verloren gehen. Fotos bleiben nur während der aktuellen Sitzung sichtbar.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preise & Zustand',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text(
              'Cardmarket-Preise werden über TCGdex in EUR geladen. Das Abrufdatum der Quelle steht an jeder Karte. Marktpreise können mehrere Sprachen und Zustände zusammenfassen; sie sind kein konkretes Verkaufsangebot.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            SizedBox(height: 12),
            Text(
              'Die Zustandsprüfung ist eine geführte Selbsteinschätzung zu Ecken, Kanten und Oberfläche. Sie erkennt weder Echtheit noch unsichtbare Schäden und ersetzt kein professionelles Grading.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      TextButton.icon(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'PokéLens',
          applicationVersion: '1.0.0',
        ),
        icon: const Icon(Icons.article_outlined, size: 18),
        label: const Text('Open-Source-Lizenzen'),
      ),
    ],
  );

  Widget _notice(String text, IconData icon, {VoidCallback? onRetry}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palePurple,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 11, color: Color(0xFF71608E)),
              ),
            ),
            if (onRetry != null)
              IconButton(
                tooltip: 'Erneut versuchen',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: accent, size: 19),
              ),
          ],
        ),
      );

  Widget _footer() => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.favorite_border, size: 11, color: muted),
      SizedBox(width: 5),
      Flexible(
        child: Text(
          'Mit Liebe zum Sammeln.  ·  Unabhängiges Fanprojekt. Pokémon gehört seinen Rechteinhabern.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, color: muted),
        ),
      ),
    ],
  );

  void _showHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ein gutes Foto macht den Unterschied.'),
      content: const SingleChildScrollView(
        child: Text(
          '1. Nimm die Karte aus der Hülle und lege sie flach hin.\n\n2. Nutze Tageslicht ohne direkte Spiegelungen.\n\n3. Fotografiere die ganze Vorderseite, inklusive Kartennummer.\n\n4. Wähle die Kartensprache und bestätige den passenden Treffer.\n\n5. Prüfe Vorder- und Rückseite bei der geführten Zustandsbewertung.\n\nNutze „Foto aufnehmen“ für die Kamera oder „Aus Fotos wählen“ für ein vorhandenes Bild. Auch im Browser wird der Kartentext automatisch gelesen. Beim ersten Scan braucht das Laden der Sprachdaten eine Internetverbindung.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Alles klar'),
        ),
      ],
    ),
  );
}
