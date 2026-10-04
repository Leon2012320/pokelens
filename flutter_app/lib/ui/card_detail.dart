import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pokemon_card.dart';
import '../services/catalog_service.dart';
import '../services/collection_store.dart';
import '../models/condition_assessment.dart';
import 'widgets.dart' show CardArt;

const _ink = Color(0xFF252435);
const _muted = Color(0xFF848292);
const _purple = Color(0xFF7660DB);
const _lavender = Color(0xFFF3F0FC);
const _line = Color(0xFFEDEBF2);

Future<void> showCardDetail(
  BuildContext context, {
  required PokemonCard card,
  required CatalogService catalog,
  required CollectionStore collection,
}) async {
  final content = _CardDetail(
    card: card,
    catalog: catalog,
    collection: collection,
  );
  if (MediaQuery.sizeOf(context).width < 680) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .94,
        child: content,
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 820,
            maxHeight: MediaQuery.sizeOf(context).height - 56,
          ),
          child: content,
        ),
      ),
    );
  }
}

class _CardDetail extends StatefulWidget {
  const _CardDetail({
    required this.card,
    required this.catalog,
    required this.collection,
  });

  final PokemonCard card;
  final CatalogService catalog;
  final CollectionStore collection;

  @override
  State<_CardDetail> createState() => _CardDetailState();
}

class _CardDetailState extends State<_CardDetail> {
  late PokemonCard _card;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _saved = false;
  bool _holo = false;
  ConditionAssessment? _condition;

  @override
  void initState() {
    super.initState();
    _card = widget.card;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final card = await widget.catalog.getCard(
        widget.card.id,
        language: widget.card.language,
      );
      if (!mounted) return;
      setState(() {
        _card = card;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.collection.add(
        _card,
        condition: _condition?.label ?? 'Ungeprüft',
        variant: _holo ? 'Holo' : 'Marktstandard',
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Karte in deiner Sammlung gespeichert.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speichern fehlgeschlagen. Bitte versuche es erneut.'),
        ),
      );
    }
  }

  Future<void> _openMarket() async {
    final uri = Uri.https('www.cardmarket.com', '/de/Pokemon/Products/Search', {
      'searchString': '${_card.name} ${_card.localId}',
    });
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Could not open Cardmarket');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cardmarket konnte nicht geöffnet werden.'),
        ),
      );
    }
  }

  Future<void> _assess() async {
    final result = await showDialog<ConditionAssessment>(
      context: context,
      builder: (context) => _AssessmentDialog(initial: _condition),
    );
    if (!mounted || result == null) return;
    setState(() {
      _condition = result;
      _saved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 14, 12),
          child: Row(
            children: [
              const Icon(Icons.style_outlined, color: _purple, size: 21),
              const SizedBox(width: 10),
              const Text(
                'Kartendetails',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: _ink,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Schließen',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 22, color: _muted),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 610;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: _art()),
                      const SizedBox(width: 30),
                      Expanded(flex: 6, child: _information()),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _art(compact: true),
                    const SizedBox(height: 24),
                    _information(),
                  ],
                );
              },
            ),
          ),
        ),
        const Divider(height: 1, color: _line),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _saved ? const Color(0xFF327E6A) : _purple,
                  disabledBackgroundColor: _saved
                      ? const Color(0xFF327E6A)
                      : null,
                  disabledForegroundColor: _saved ? Colors.white : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving || _saved ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _saved ? Icons.check_rounded : Icons.add_rounded,
                        size: 20,
                      ),
                label: Text(
                  _saved ? 'In deiner Sammlung' : 'Zur Sammlung hinzufügen',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _art({bool compact = false}) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: compact ? 290 : 368,
          padding: EdgeInsets.all(compact ? 20 : 26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF3F0FC), Color(0xFFF7F7FB)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: CardArt(card: _card),
        ),
        const SizedBox(height: 13),
        const Text(
          'Katalogbild · tatsächlicher Zustand kann abweichen',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, height: 1.5, color: _muted),
        ),
      ],
    );
  }

  Widget _information() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _Tag(_card.language.toUpperCase()),
            _Tag('#${_card.displayNumber}', neutral: true),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          _card.name,
          style: const TextStyle(
            fontSize: 29,
            height: 1.2,
            letterSpacing: -.8,
            color: _ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          _card.setName,
          style: const TextStyle(fontSize: 13, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (_loading) ...[
          const Row(
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _purple,
                ),
              ),
              SizedBox(width: 9),
              Text(
                'Marktdaten werden geladen …',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (_failed) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 5, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8ED),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Marktdaten gerade nicht erreichbar.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8B6B2F)),
                  ),
                ),
                TextButton(
                  onPressed: _load,
                  child: const Text('Erneut', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _marketPanel(),
        const SizedBox(height: 23),
        const Divider(height: 1, color: _line),
        const SizedBox(height: 21),
        Row(
          children: [
            const Icon(Icons.verified_outlined, size: 18, color: _purple),
            const SizedBox(width: 8),
            const Text(
              'Kartenzustand',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _ink,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Text(
              _condition?.code ?? 'Offen',
              style: const TextStyle(
                fontSize: 11,
                color: _purple,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          _condition?.label ?? 'Noch nicht eingeschätzt',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _condition?.explanation ??
              'Prüfe Ecken, Kanten und Oberfläche deiner Karte.',
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _assess,
          style: OutlinedButton.styleFrom(
            foregroundColor: _purple,
            side: const BorderSide(color: Color(0xFFE1DDF2)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          ),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: Text(
            _condition == null
                ? 'Zustand einschätzen'
                : 'Einschätzung bearbeiten',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Geführte Einschätzung · kein professionelles Grading',
          style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
        ),
      ],
    );
  }

  Widget _marketPanel() {
    final market = _card.market;
    final trend = _holo ? market?.holoTrend : market?.trend;
    final low = _holo ? market?.holoLow : market?.low;
    final avg7 = _holo ? market?.holoAvg7 : market?.avg7;
    final avg30 = _holo ? market?.holoAvg30 : market?.avg30;
    final currency = market?.currency ?? 'EUR';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'CARDMARKET',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: _muted,
              ),
            ),
            const Spacer(),
            if ((market?.holoTrend ?? 0) > 0)
              DropdownButtonHideUnderline(
                child: DropdownButton<bool>(
                  value: _holo,
                  isDense: true,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: _muted,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('Marktstandard'),
                    ),
                    DropdownMenuItem(value: true, child: Text('Holo')),
                  ],
                  onChanged: (value) => setState(() {
                    _holo = value ?? false;
                    _saved = false;
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          _money(trend, currency),
          style: const TextStyle(
            fontSize: 38,
            height: 1.25,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: _ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          trend == null || trend <= 0
              ? 'Kein Preistrend verfügbar'
              : 'Preistrend',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 17),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F7FA),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              Expanded(child: _PriceStat('Ab', _money(low, currency))),
              Expanded(child: _PriceStat('Ø 7 Tage', _money(avg7, currency))),
              Expanded(child: _PriceStat('Ø 30 Tage', _money(avg30, currency))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Stand: ${_date(market?.updated)} · Cardmarket via TCGdex',
          style: const TextStyle(fontSize: 10, color: _muted, height: 1.6),
        ),
        const SizedBox(height: 6),
        const Text(
          'Marktdurchschnitt über Sprachen und Zustände. Dein Verkaufspreis hängt von Variante, Sprache und Erhaltung ab.',
          style: TextStyle(fontSize: 11, height: 1.65, color: _muted),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _openMarket,
          style: TextButton.styleFrom(
            foregroundColor: _purple,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 14),
          label: const Text(
            'Angebote auf Cardmarket',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

String _money(num? amount, String currency) {
  if (amount == null || amount <= 0 || !amount.isFinite) return '—';
  final parts = amount.toStringAsFixed(2).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '$whole,${parts.last} ${currency == 'EUR' ? '€' : currency}';
}

String _date(Object? value) {
  if (value == null || value.toString().isEmpty) return 'nicht verfügbar';
  final parsed = value is DateTime
      ? value
      : DateTime.tryParse(value.toString());
  if (parsed == null) return value.toString();
  return '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year}';
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.neutral = false});
  final String label;
  final bool neutral;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: neutral ? const Color(0xFFF6F5F8) : _lavender,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 10,
        color: neutral ? _muted : _purple,
      ),
    ),
  );
}

class _PriceStat extends StatelessWidget {
  const _PriceStat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          color: _ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _AssessmentDialog extends StatefulWidget {
  const _AssessmentDialog({this.initial});
  final ConditionAssessment? initial;

  @override
  State<_AssessmentDialog> createState() => _AssessmentDialogState();
}

class _AssessmentDialogState extends State<_AssessmentDialog> {
  WearLevel? _corners;
  WearLevel? _edges;
  WearLevel? _surface;
  bool _creased = false;

  @override
  void initState() {
    super.initState();
    _corners = widget.initial?.corners;
    _edges = widget.initial?.edges;
    _surface = widget.initial?.surface;
    _creased = widget.initial?.creased ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ready = _corners != null && _edges != null && _surface != null;
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Schau genauer hin.',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: _ink,
          fontSize: 22,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Betrachte Vorder- und Rückseite bei gutem Licht, möglichst ohne Hülle.',
                style: TextStyle(fontSize: 13, color: _muted, height: 1.65),
              ),
              const SizedBox(height: 22),
              _wearInput(
                'Ecken',
                'Abnutzung, weiße Stellen oder abgerundete Ecken',
                _corners,
                (value) => setState(() => _corners = value),
              ),
              const SizedBox(height: 18),
              _wearInput(
                'Kanten',
                'Weiße Ränder, Abplatzer oder Beschädigungen',
                _edges,
                (value) => setState(() => _edges = value),
              ),
              const SizedBox(height: 18),
              _wearInput(
                'Oberfläche',
                'Kratzer, Druckstellen, Flecken oder Abrieb',
                _surface,
                (value) => setState(() => _surface = value),
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: _purple,
                title: const Text(
                  'Knicke oder Risse',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                subtitle: const Text(
                  'Auch kleine Knicke berücksichtigen',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
                value: _creased,
                onChanged: (value) => setState(() => _creased = value),
              ),
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: _lavender,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Geführte Einschätzung · kein professionelles Grading. Deine Angaben bestimmen das Ergebnis. Es ist keine Echtheitsprüfung.',
                  style: TextStyle(fontSize: 11, height: 1.6, color: _purple),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _purple,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          onPressed: ready
              ? () => Navigator.of(context).pop(
                  ConditionAssessment(
                    corners: _corners!,
                    edges: _edges!,
                    surface: _surface!,
                    creased: _creased,
                  ),
                )
              : null,
          child: const Text('Einschätzung übernehmen'),
        ),
      ],
    );
  }

  Widget _wearInput(
    String label,
    String hint,
    WearLevel? value,
    ValueChanged<WearLevel?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: _ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: const TextStyle(fontSize: 11, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<WearLevel>(
          initialValue: value,
          hint: const Text(
            'Bitte auswählen',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: _ink),
          icon: const Icon(Icons.expand_more_rounded, color: _muted),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFFAF9FC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: const BorderSide(color: _line),
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: WearLevel.none,
              child: Text('Keine sichtbare Abnutzung'),
            ),
            DropdownMenuItem(
              value: WearLevel.light,
              child: Text('Leichte Abnutzung'),
            ),
            DropdownMenuItem(
              value: WearLevel.moderate,
              child: Text('Deutliche Abnutzung'),
            ),
            DropdownMenuItem(
              value: WearLevel.severe,
              child: Text('Starke Abnutzung'),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
