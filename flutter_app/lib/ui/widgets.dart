import 'package:flutter/material.dart';
import '../models/pokemon_card.dart';
import 'theme.dart';

class LensLogo extends StatelessWidget {
  const LensLogo({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Center(
      child: CustomPaint(
        size: Size(size * .62, size * .62),
        painter: _LensPainter(),
      ),
    ),
  );
}

class _LensPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    for (int i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(w / 2, w / 2);
      canvas.rotate(i * 1.5708);
      canvas.translate(-w / 2, -w / 2);
      canvas.drawPath(
        Path()
          ..moveTo(0, w * .29)
          ..lineTo(0, w * .09)
          ..quadraticBezierTo(0, 0, w * .09, 0)
          ..lineTo(w * .29, 0),
        p,
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset(w / 2, w / 2), w * .27, p);
    canvas.drawCircle(Offset(w / 2, w / 2), w * .07, p);
    canvas.drawLine(Offset(w * .23, w / 2), Offset(w * .40, w / 2), p);
    canvas.drawLine(Offset(w * .60, w / 2), Offset(w * .77, w / 2), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.color = accent,
    this.background = palePurple,
    this.icon,
  });
  final String text;
  final Color color, background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class CardArt extends StatelessWidget {
  const CardArt({super.key, required this.card, this.fit = BoxFit.contain});
  final PokemonCard card;
  final BoxFit fit;
  static const localIds = {
    'sv03.5-199',
    'sv03.5-151',
    'swsh7-215',
    'sv04.5-234',
  };
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        color: palePurple,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.style_outlined, size: 50, color: accent),
      ),
    );
    if (localIds.contains(card.id) && card.language == 'de') {
      return Image.asset(
        'assets/cards/${card.id}.webp',
        fit: fit,
        errorBuilder: (_, e, s) => fallback,
      );
    }
    if (card.imageUrl == null) return fallback;
    return Image.network(
      card.imageUrl!,
      fit: fit,
      errorBuilder: (_, e, s) => fallback,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class CatalogTile extends StatefulWidget {
  const CatalogTile({
    super.key,
    required this.card,
    required this.onTap,
    this.index = 0,
    this.footer,
  });
  final PokemonCard card;
  final VoidCallback onTap;
  final int index;
  final Widget? footer;
  @override
  State<CatalogTile> createState() => _CatalogTileState();
}

class _CatalogTileState extends State<CatalogTile> {
  bool hovered = false;
  static const colors = [
    Color(0xFFF7F0EA),
    Color(0xFFF2EEF9),
    Color(0xFFEEF2F4),
    Color(0xFFF0F3EA),
  ];
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hovered ? accent.withValues(alpha: .45) : line,
        ),
        boxShadow: [
          if (hovered)
            BoxShadow(
              color: accent.withValues(alpha: .09),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: colors[widget.index % colors.length],
                        padding: const EdgeInsets.fromLTRB(25, 17, 25, 17),
                        child: AnimatedScale(
                          scale: hovered ? 1.04 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: CardArt(card: widget.card),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Pill(
                        widget.card.language.toUpperCase(),
                        color: ink,
                        background: Colors.white.withValues(alpha: .9),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.card.setName} · ${widget.card.displayNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.card.market?.trend == null
                                ? 'Preis ansehen'
                                : euro(widget.card.market?.trend),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -.4,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.north_east_rounded,
                          size: 15,
                          color: muted,
                        ),
                      ],
                    ),
                    if (widget.footer != null) ...[
                      const SizedBox(height: 9),
                      widget.footer!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: palePurple,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, size: 30, color: accent),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.7),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}
