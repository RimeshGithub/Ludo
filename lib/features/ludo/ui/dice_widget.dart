import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ludo_style.dart';
import 'ludo_theme.dart';

/// Tap-to-roll dice. Shakes while [rolling]; glows when [enabled].
/// The look comes from [skin] (see the Dice section of the theme picker).
class DiceWidget extends StatefulWidget {
  const DiceWidget({
    super.key,
    required this.value,
    required this.rolling,
    required this.enabled,
    required this.accent,
    required this.onTap,
    this.skin = DiceSkin.classic,
    this.size = 84,
  });

  final int value;
  final bool rolling;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;
  final DiceSkin skin;
  final double size;

  @override
  State<DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<DiceWidget> with TickerProviderStateMixin {
  /// Shake while rolling. Runs only during a roll.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  /// Slow "breathing" of the idle glow. It goes up and back down (reverse
  /// repeat) with an eased curve, so there is no jump at the loop point.
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  /// Glow brightness at the dim and bright ends of one breath (0..1).
  static const double _dimLevel = 0.05;
  static const double _peakLevel = 1;

  /// Fades the glow in when the die becomes tappable and out when it stops
  /// being tappable, instead of popping in and out of the tree.
  late final AnimationController _show =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

  @override
  void initState() {
    super.initState();
    _show.addStatusListener((status) {
      // Fully faded out: stop ticking, nothing is visible.
      if (status == AnimationStatus.dismissed) _pulse.stop();
    });
    _sync();
  }

  @override
  void didUpdateWidget(covariant DiceWidget old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.rolling) {
      if (!_c.isAnimating) _c.repeat();
    } else if (_c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }

    if (widget.enabled && !widget.rolling) {
      _show.forward();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _show.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _pulse.dispose();
    _show.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Dice, showing ${widget.value}. ${widget.enabled ? "Tap to roll" : ""}',
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        // The face and the halo are each painted once into their own layer;
        // while animating, only the halo's opacity (or the shake transform)
        // changes, so no blur or gradient is re-rasterised per frame.
        child: AnimatedBuilder(
          animation: _c,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Glow. Always in the tree (no pop-in / pop-out); its opacity
              // does all the work.
              AnimatedBuilder(
                animation: Listenable.merge([_show, _pulse]),
                child: RepaintBoundary(
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.size * widget.skin.radius),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accent.withValues(alpha: 0.65),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                builder: (context, halo) {
                  final breathe = Curves.easeInOutSine.transform(_pulse.value);
                  final fade = Curves.easeInOut.transform(_show.value);
                  // Dim <-> bright: from 0.10 (almost off) up to 0.95. Never
                  // 1.0: at exactly 1.0 Flutter drops the opacity layer for
                  // that frame, and the switch between the layered and
                  // un-layered paths is the flicker on Android.
                  final level = _dimLevel + (_peakLevel - _dimLevel) * breathe;
                  // A slight swell with the brightness makes it read as a
                  // glow breathing in and out. Paint-only, so it is cheap.
                  return Transform.scale(
                    scale: 0.94 + 0.15 * breathe,
                    child: Opacity(opacity: fade * level, child: halo),
                  );
                },
              ),
              RepaintBoundary(
                child: DiceFace(
                  value: widget.value,
                  size: widget.size,
                  skin: widget.skin,
                  accent: widget.accent,
                  enabled: widget.enabled,
                  glow: 0,
                ),
              ),
            ],
          ),
          builder: (context, face) {
            if (!widget.rolling) return face!;
            final shake = math.sin(_c.value * math.pi * 8);
            return Transform.rotate(
              angle: shake * 0.28,
              child: Transform.translate(offset: Offset(shake * 4, 0), child: face),
            );
          },
        ),
      ),
    );
  }
}

/// One static die face. Used by [DiceWidget] in the game and by the previews
/// in the theme picker, so both always look the same.
class DiceFace extends StatelessWidget {
  const DiceFace({
    super.key,
    required this.value,
    required this.size,
    required this.skin,
    required this.accent,
    this.enabled = true,
    this.glow = 0,
  });

  final int value;
  final double size;
  final DiceSkin skin;

  /// Colour of the player whose turn it is (used by skins that follow it).
  final Color accent;

  /// An idle die has a muted border (and dark pips on skins that follow the
  /// player's colour).
  final bool enabled;

  /// 0..1 pulse strength of the halo around the die.
  final double glow;

  @override
  Widget build(BuildContext context) {
    final s = size;
    final bw = math.max(1.5, skin.borderWidth * s / 84);
    final bodyColors = skin.fromAccent
        ? [LudoPalette.tint(accent, 0.22), LudoPalette.shade(accent, 0.28)]
        : skin.body;
    final edge = skin.edge != null
        ? (enabled ? skin.edge! : skin.edge!.withValues(alpha: 0.5))
        : (enabled ? accent : Colors.grey.shade500);
    final base = skin.pip ?? (enabled ? accent : Colors.black87);
    final pip = (skin.pip == null && (value == 6 || value == 1)) ? LudoPalette.shade(base, 0.1) : base;

    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bodyColors,
        ),
        borderRadius: BorderRadius.circular(s * skin.radius),
        border: Border.all(color: edge, width: bw),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25 + 0.45 * glow),
            blurRadius: 6 + 14 * glow,
            spreadRadius: 1 + 2 * glow,
          ),
          const BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 3)),
        ],
      ),
      child: CustomPaint(
        painter: _DiePainter(
          value: value,
          skin: skin,
          pip: pip,
          corner: math.max(0.0, s * skin.radius - bw),
        ),
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  _DiePainter({required this.value, required this.skin, required this.pip, required this.corner});

  final int value;
  final DiceSkin skin;
  final Color pip;
  final double corner;

  static const _layout = <int, List<Offset>>{
    1: [Offset(.5, .5)],
    2: [Offset(.28, .28), Offset(.72, .72)],
    3: [Offset(.28, .28), Offset(.5, .5), Offset(.72, .72)],
    4: [Offset(.28, .28), Offset(.72, .28), Offset(.28, .72), Offset(.72, .72)],
    5: [Offset(.28, .28), Offset(.72, .28), Offset(.5, .5), Offset(.28, .72), Offset(.72, .72)],
    6: [Offset(.3, .26), Offset(.7, .26), Offset(.3, .5), Offset(.7, .5), Offset(.3, .74), Offset(.7, .74)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(corner));

    // Surface decoration, kept inside the rounded body.
    if (skin.grain || skin.shine) {
      canvas.save();
      canvas.clipRRect(body);
      if (skin.grain) _grain(canvas, size);
      if (skin.shine) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment(0.15, 0.15),
              colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
            ).createShader(Offset.zero & size),
        );
      }
      canvas.restore();
    }

    final r = size.width * 0.085;
    for (final o in _layout[value.clamp(1, 6)]!) {
      final c = Offset(o.dx * size.width, o.dy * size.height);
      if (skin.glowPips) {
        canvas.drawPath(
          _pipPath(skin.pipShape, c, r * 1.25),
          Paint()
            ..color = pip.withValues(alpha: 0.7)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.9),
        );
      }
      if (skin.engraved) {
        // Light lip on the lower-right edge makes the pip look carved in.
        canvas.drawPath(
          _pipPath(skin.pipShape, c.translate(r * 0.22, r * 0.26), r),
          Paint()..color = Colors.white.withValues(alpha: 0.55),
        );
      }
      canvas.drawPath(_pipPath(skin.pipShape, c, r), Paint()..color = pip);
    }
  }

  void _grain(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.width * 0.018)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF5B3A1A).withValues(alpha: 0.2);
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.1 + i * 0.13);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width + 4; x += 4) {
        path.lineTo(x, y + math.sin(x / size.width * 5 + i * 1.7) * size.height * 0.018);
      }
      canvas.drawPath(path, p);
    }
  }

  Path _pipPath(PipShape shape, Offset c, double r) {
    switch (shape) {
      case PipShape.round:
        return Path()..addOval(Rect.fromCircle(center: c, radius: r));
      case PipShape.square:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.75, height: r * 1.75),
            Radius.circular(r * 0.2),
          ));
      case PipShape.diamond:
        return _polygon(c, r * 1.3, 4, -math.pi / 2);
      case PipShape.star:
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final rr = i.isEven ? r * 1.45 : r * 0.62;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        return path..close();
    }
  }

  Path _polygon(Offset c, double r, int n, double rot) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      final a = rot + 2 * math.pi * i / n;
      final pt = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    return path..close();
  }

  // The die is repainted every frame while it pulses anyway, and the skin is
  // rebuilt on demand, so a cheap "always repaint" is simplest and correct.
  @override
  bool shouldRepaint(_DiePainter old) => true;
}