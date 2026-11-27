import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'ludo_style.dart';
import 'ludo_theme.dart';

/// Paints the static part of a board (yards, track, home lanes, centre hub).
/// Everything is derived from [BoardLayout], so each player count gets its
/// own geometry automatically. Tokens are separate widgets so they can animate.
///
/// The look (surface texture, frame, cell shape, yard shape, markers, lane
/// decoration, centre) comes from the [BoardStyle] of [style], including any
/// tweaks the player made in the theme picker.
class BoardPainter extends CustomPainter {
  BoardPainter(this.layout, [this.style = const LudoStyle(), this.preview = false, this.teamOfArm]);

  final BoardLayout layout;

  /// Team mode only: board arm -> team id. Yards of the same team get the same
  /// numbered badge and ring colour. Null when teams are off.
  final Map<int, int>? teamOfArm;
  final LudoStyle style;

  /// Small thumbnails skip the drop shadow so nothing spills outside them.
  final bool preview;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final scale = side / (2 * layout.extent);
    final c = Offset(size.width / 2, size.height / 2);
    Offset px(Pt p) => Offset(c.dx + p.x * scale, c.dy + p.y * scale);

    final bs = style.boardStyle;
    final active = layout.seatArms.toSet();
    Color armColor(int arm) => active.contains(arm) ? LudoPalette.seat(arm) : bs.inactive;

    // Board surface, texture and frame.
    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: side, height: side),
      Radius.circular(scale * 1.1),
    );
    if (!preview) canvas.drawShadow(Path()..addRRect(bg), Colors.black, 14, true);
    canvas.drawRRect(
      bg,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bs.bg,
        ).createShader(bg.outerRect),
    );
    _pattern(canvas, bg, bs, scale, c, side);
    _frame(canvas, bg, bs, scale);

    // Home yards.
    for (var k = 0; k < layout.arms; k++) {
      _yard(canvas, bs, px(layout.yardCenter(k)), layout.yardRadius * scale, scale, armColor(k),
          active.contains(k), k);
      final t = teamOfArm?[k];
      if (t != null && active.contains(k)) {
        _teamBadge(canvas, c, px(layout.yardCenter(k)), layout.yardRadius * scale, scale, t);
      }
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, scale * 0.04)
      ..strokeJoin = StrokeJoin.round
      ..color = bs.cellStroke;
    final cellSize = scale * 0.92 * bs.cellScale;

    // Optional continuous road under the track and the home lanes.
    if (bs.ribbon != null) _ribbon(canvas, bs, scale, px, armColor);

    // Shared track.
    for (var i = 0; i < layout.ringLength; i++) {
      var fill = bs.cellFill;
      var isStart = false;
      if (layout.startCells.contains(i)) {
        isStart = true;
        final arm = (i - (layout.armLength + 2)) ~/ layout.segmentLength;
        fill = armColor(arm);
      }
      final o = px(layout.ringPoints[i]);
      _cell(canvas, o, layout.ringAngles[i], cellSize, fill, bs, stroke);
      if (isStart) {
        _mark(canvas, o, scale * 0.3, bs.mark == MarkStyle.none ? MarkStyle.star : bs.mark, Colors.white);
      } else if (layout.starCells.contains(i)) {
        _mark(canvas, o, scale * 0.3, bs.mark, bs.markColor);
      }
    }

    // Home lanes.
    for (var k = 0; k < layout.arms; k++) {
      final col = armColor(k);
      for (var i = 0; i < layout.laneLength; i++) {
        final o = px(layout.lanePoints[k][i]);
        final angle = layout.armAngle(k);
        final path = _cell(canvas, o, angle, cellSize, LudoPalette.tint(col, 0.28), bs, stroke);
        _laneDecor(canvas, bs.lane, path, o, angle, cellSize);
      }
    }

    _hub(canvas, bs, c, scale, armColor);
  }

  // ----------------------------------------------------------------- surface

  void _pattern(Canvas canvas, RRect bg, BoardStyle bs, double scale, Offset c, double side) {
    if (bs.pattern == SurfacePattern.none) return;
    final rect = bg.outerRect;
    final n = (side / 2 / scale).ceil() + 1;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, scale * 0.045)
      ..strokeCap = StrokeCap.round
      ..color = bs.patternColor;
    final fill = Paint()..color = bs.patternColor;

    canvas.save();
    canvas.clipRRect(bg);
    switch (bs.pattern) {
      case SurfacePattern.none:
        break;
      case SurfacePattern.grid:
        for (var k = -n; k <= n; k++) {
          final d = k * scale;
          canvas.drawLine(Offset(c.dx + d, rect.top), Offset(c.dx + d, rect.bottom), line);
          canvas.drawLine(Offset(rect.left, c.dy + d), Offset(rect.right, c.dy + d), line);
        }
      case SurfacePattern.dots:
        for (var i = -n; i < n; i++) {
          for (var j = -n; j < n; j++) {
            canvas.drawCircle(
              Offset(c.dx + (i + 0.5) * scale, c.dy + (j + 0.5) * scale),
              scale * 0.075,
              fill,
            );
          }
        }
      case SurfacePattern.checker:
        final step = scale * 1.5;
        final m = (side / 2 / step).ceil() + 1;
        for (var i = -m; i < m; i++) {
          for (var j = -m; j < m; j++) {
            if ((i + j).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(c.dx + (i - 0.5) * step, c.dy + (j - 0.5) * step, step, step),
                fill,
              );
            }
          }
        }
      case SurfacePattern.diagonal:
        final step = scale * 1.1;
        final m = (side / step).ceil() + 1;
        for (var k = -m; k <= m; k++) {
          final x = rect.left + k * step;
          canvas.drawLine(Offset(x, rect.top), Offset(x + side, rect.bottom), line);
        }
      case SurfacePattern.wood:
        final rnd = math.Random(11);
        final rows = (side / (scale * 0.6)).ceil();
        for (var r = 0; r <= rows; r++) {
          final y = rect.top + r * scale * 0.6;
          final phase = rnd.nextDouble() * 6;
          final amp = scale * (0.05 + 0.08 * rnd.nextDouble());
          final freq = 0.5 + 0.5 * rnd.nextDouble();
          final path = Path()..moveTo(rect.left, y);
          for (var x = rect.left; x <= rect.right + scale; x += scale * 0.4) {
            path.lineTo(x, y + math.sin((x - rect.left) / scale * freq + phase) * amp);
          }
          final w = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * (0.03 + 0.05 * rnd.nextDouble())
            ..strokeCap = StrokeCap.round
            ..color = bs.patternColor.withValues(alpha: bs.patternColor.a * (0.5 + 0.5 * rnd.nextDouble()));
          canvas.drawPath(path, w);
        }
        // A few knots.
        for (var i = 0; i < 4; i++) {
          final o = Offset(rect.left + side * rnd.nextDouble(), rect.top + side * rnd.nextDouble());
          final kr = scale * (0.22 + 0.2 * rnd.nextDouble());
          for (var ring = 1; ring <= 3; ring++) {
            canvas.drawOval(
              Rect.fromCenter(center: o, width: kr * ring * 1.9, height: kr * ring * 0.9),
              line..strokeWidth = scale * 0.03,
            );
          }
        }
      case SurfacePattern.waves:
        final rows = (side / scale).ceil();
        for (var r = 0; r <= rows; r++) {
          final y = rect.top + r * scale * 1.0;
          final path = Path()..moveTo(rect.left, y);
          for (var x = rect.left; x <= rect.right + scale; x += scale * 0.3) {
            path.lineTo(x, y + math.sin((x - rect.left) / scale * 2.4 + r * 1.3) * scale * 0.17);
          }
          canvas.drawPath(path, line);
        }
      case SurfacePattern.stars:
        final rnd = math.Random(5);
        for (var i = 0; i < 56; i++) {
          final o = Offset(rect.left + side * rnd.nextDouble(), rect.top + side * rnd.nextDouble());
          final rr = scale * (0.05 + 0.13 * rnd.nextDouble());
          final p = Paint()
            ..color = bs.patternColor.withValues(alpha: bs.patternColor.a * (0.35 + 0.65 * rnd.nextDouble()));
          if (i % 3 == 0) {
            _star(canvas, o, rr * 1.7, p, points: 4, inner: 0.28);
          } else {
            canvas.drawCircle(o, rr * 0.55, p);
          }
        }
    }
    canvas.restore();
  }

  void _frame(Canvas canvas, RRect bg, BoardStyle bs, double scale) {
    final rect = bg.outerRect;
    final w = scale * 0.2;
    final grad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: bs.edge,
    ).createShader(rect);

    if (bs.frame == FrameStyle.glow) {
      canvas.drawRRect(
        bg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 2.2
          ..color = bs.edge.first.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.8),
      );
    }
    canvas.drawRRect(
      bg,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = grad,
    );

    final accent = bs.edge.first;
    switch (bs.frame) {
      case FrameStyle.plain:
      case FrameStyle.glow:
        break;
      case FrameStyle.double:
        canvas.drawRRect(
          bg.deflate(scale * 0.28),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * 0.05
            ..color = accent.withValues(alpha: 0.85),
        );
      case FrameStyle.dashed:
        final inner = Path()..addRRect(bg.deflate(scale * 0.34));
        _dashed(
          canvas,
          inner,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * 0.065
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: 0.9),
          scale * 0.3,
          scale * 0.22,
        );
      case FrameStyle.studded:
        final ring = rect.deflate(scale * 0.42);
        final len = ring.width;
        final count = math.max(4, (len / (scale * 1.5)).round());
        final stud = Paint()..color = accent;
        final studShade = Paint()..color = bs.edge.last;
        for (var s = 0; s < 4; s++) {
          for (var i = 0; i < count; i++) {
            final t = i / count * len;
            final o = switch (s) {
              0 => Offset(ring.left + t, ring.top),
              1 => Offset(ring.right, ring.top + t),
              2 => Offset(ring.right - t, ring.bottom),
              _ => Offset(ring.left, ring.bottom - t),
            };
            canvas.drawCircle(o + Offset(0, scale * 0.025), scale * 0.115, studShade);
            canvas.drawCircle(o, scale * 0.105, stud);
            canvas.drawCircle(
              o + Offset(-scale * 0.03, -scale * 0.03),
              scale * 0.035,
              Paint()..color = Colors.white.withValues(alpha: 0.7),
            );
          }
        }
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  // ------------------------------------------------------------------- yards

  void _yard(Canvas canvas, BoardStyle bs, Offset yc, double yr, double scale, Color col,
      bool isActive, int arm) {
    final outer = _yardPath(bs.yardShape, yc, yr);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: [LudoPalette.tint(col, 0.3), col, LudoPalette.shade(col, 0.25)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: yc, radius: yr)),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale * 0.05
        ..strokeJoin = StrokeJoin.round
        ..color = LudoPalette.shade(col, 0.35).withValues(alpha: 0.6),
    );
    canvas.drawPath(
      _yardPath(bs.yardShape, yc, yr * 0.82),
      Paint()..color = isActive ? bs.yardInner.withValues(alpha: 0.93) : bs.yardInner.withValues(alpha: 0.6),
    );
    if (!isActive) return;

    for (var i = 0; i < 4; i++) {
      final s = Offset(
        yc.dx + (layout.yardSlot(arm, i).x - layout.yardCenter(arm).x) * scale,
        yc.dy + (layout.yardSlot(arm, i).y - layout.yardCenter(arm).y) * scale,
      );
      final r = scale * 0.47;
      switch (bs.slot) {
        case SlotStyle.ring:
          canvas.drawCircle(s, r, Paint()..color = col.withValues(alpha: 0.2));
          canvas.drawCircle(
            s,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = scale * 0.06
              ..color = col.withValues(alpha: 0.55),
          );
        case SlotStyle.dimple:
          canvas.drawCircle(s, r, Paint()..color = col.withValues(alpha: 0.28));
          canvas.drawArc(
            Rect.fromCircle(center: s, radius: r * 0.9),
            math.pi * 0.7,
            math.pi,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = scale * 0.1
              ..strokeCap = StrokeCap.round
              ..color = Colors.black.withValues(alpha: 0.22),
          );
          canvas.drawArc(
            Rect.fromCircle(center: s, radius: r * 0.9),
            -math.pi * 0.3,
            math.pi,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = scale * 0.06
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: 0.5),
          );
        case SlotStyle.square:
          final rr = RRect.fromRectAndRadius(
            Rect.fromCenter(center: s, width: r * 1.8, height: r * 1.8),
            Radius.circular(r * 0.3),
          );
          canvas.drawRRect(rr, Paint()..color = col.withValues(alpha: 0.22));
          canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = scale * 0.06
              ..color = col.withValues(alpha: 0.6),
          );
        case SlotStyle.mark:
          canvas.drawCircle(s, r, Paint()..color = col.withValues(alpha: 0.13));
          _mark(canvas, s, r * 0.72, bs.mark == MarkStyle.none ? MarkStyle.star : bs.mark,
              col.withValues(alpha: 0.6));
      }
    }
  }

  /// Team marker on a yard: a numbered badge in its centre. Partners share the same colour and number.
  void _teamBadge(Canvas canvas, Offset boardCenter, Offset yc, double yr, double scale, int team) {
    final col = LudoPalette.team(team);
    // Badge sits in the middle of the yard, between the four token slots.
    final o = yc;
    final r = scale * 0.35;
    canvas.drawCircle(o + Offset(0, scale * 0.05), r, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(o, r, Paint()..color = col);
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = scale * 0.04
        ..color = Colors.black.withValues(alpha: 0.5),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: LudoPalette.teamName(team),
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.6),
          fontWeight: FontWeight.w900,
          fontSize: r * 1.25,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final textOffset = Offset(
      o.dx - tp.width / 2,
      o.dy - tp.height / 2,
    );

    tp.paint(canvas, textOffset);
  }

  Path _yardPath(YardShape shape, Offset c, double r) {
    switch (shape) {
      case YardShape.circle:
        return Path()..addOval(Rect.fromCircle(center: c, radius: r));
      case YardShape.rounded:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.8, height: r * 1.8),
            Radius.circular(r * 0.36),
          ));
      case YardShape.octagon:
        return _poly(c, r * 1.02, 8, math.pi / 8);
      case YardShape.hexagon:
        return _poly(c, r * 1.04, 6, -math.pi / 2);
      case YardShape.scallop:
        final path = Path();
        const steps = 160;
        for (var i = 0; i <= steps; i++) {
          final a = 2 * math.pi * i / steps;
          final rr = r * (0.88 + 0.12 * math.sin(a * 8).abs());
          final p = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        return path..close();
    }
  }

  Path _poly(Offset c, double r, int n, double rot) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      final a = rot + 2 * math.pi * i / n;
      final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  // ------------------------------------------------------------- track cells

  void _ribbon(Canvas canvas, BoardStyle bs, double scale, Offset Function(Pt) px,
      Color Function(int) armColor) {
    final base = bs.ribbon!;
    final edge = Color.lerp(base, Colors.black, 0.28)!;

    final ring = Path();
    for (var i = 0; i < layout.ringLength; i++) {
      final p = px(layout.ringPoints[i]);
      if (i == 0) {
        ring.moveTo(p.dx, p.dy);
      } else {
        ring.lineTo(p.dx, p.dy);
      }
    }
    ring.close();

    Paint road(Color col, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = col;

    final lanes = <(Path, Color)>[];
    for (var k = 0; k < layout.arms; k++) {
      final p = Path();
      final tip = px(layout.ringPoints[layout.tipCell(k)]);
      p.moveTo(tip.dx, tip.dy);
      for (final pt in layout.lanePoints[k]) {
        final o = px(pt);
        p.lineTo(o.dx, o.dy);
      }
      lanes.add((p, LudoPalette.tint(armColor(k), 0.2)));
    }

    canvas.drawPath(ring, road(edge, scale * 1.2));
    for (final (p, _) in lanes) {
      canvas.drawPath(p, road(edge, scale * 1.2));
    }
    canvas.drawPath(ring, road(base, scale * 1.06));
    for (final (p, col) in lanes) {
      canvas.drawPath(p, road(Color.lerp(base, col, 0.45)!, scale * 1.06));
    }
  }

  Path _cellPath(CellShape shape, double size) {
    switch (shape) {
      case CellShape.rounded:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: size, height: size),
            Radius.circular(size * 0.18),
          ));
      case CellShape.square:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: size, height: size),
            Radius.circular(size * 0.04),
          ));
      case CellShape.circle:
        return Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: size * 0.5));
      case CellShape.diamond:
        return _poly(Offset.zero, size * 0.54, 4, -math.pi / 2);
      case CellShape.hexagon:
        return _poly(Offset.zero, size * 0.52, 6, math.pi / 6);
    }
  }

  /// Draws one cell and returns its outline (in canvas coordinates).
  Path _cell(Canvas canvas, Offset o, double angle, double size, Color fill, BoardStyle bs,
      Paint stroke) {
    final m = Matrix4.translationValues(o.dx, o.dy, 0)..rotateZ(angle);
    final path = _cellPath(bs.cellShape, size).transform(m.storage);

    switch (bs.cellDepth) {
      case CellDepth.flat:
        canvas.drawPath(path, Paint()..color = fill);
      case CellDepth.raised:
        canvas.drawPath(
          path.shift(Offset(0, size * 0.07)),
          Paint()..color = Colors.black.withValues(alpha: 0.28),
        );
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [LudoPalette.tint(fill, 0.35), fill, LudoPalette.shade(fill, 0.1)],
              stops: const [0, 0.45, 1],
            ).createShader(path.getBounds()),
        );
      case CellDepth.inset:
        canvas.drawPath(path, Paint()..color = LudoPalette.shade(fill, 0.04));
        canvas.save();
        canvas.clipPath(path);
        canvas.drawPath(
          path.shift(Offset(0, size * 0.1)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.22
            ..color = Colors.black.withValues(alpha: 0.22),
        );
        canvas.restore();
    }
    canvas.drawPath(path, stroke);
    return path;
  }

  void _laneDecor(Canvas canvas, LaneStyle lane, Path path, Offset o, double angle, double size) {
    switch (lane) {
      case LaneStyle.tinted:
        break;
      case LaneStyle.striped:
        canvas.save();
        canvas.clipPath(path);
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.13
          ..color = Colors.white.withValues(alpha: 0.5);
        for (var k = -3; k <= 3; k++) {
          final d = k * size * 0.34;
          canvas.drawLine(
            Offset(o.dx + d - size, o.dy - size),
            Offset(o.dx + d + size, o.dy + size),
            p,
          );
        }
        canvas.restore();
      case LaneStyle.arrows:
        canvas.save();
        canvas.translate(o.dx, o.dy);
        canvas.rotate(angle);
        final chevron = Path()
          ..moveTo(-size * 0.26, -size * 0.14)
          ..lineTo(0, size * 0.14)
          ..lineTo(size * 0.26, -size * 0.14);
        canvas.drawPath(
          chevron,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.11
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white.withValues(alpha: 0.9),
        );
        canvas.restore();
      case LaneStyle.dots:
        canvas.drawCircle(o, size * 0.14, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
  }

  // -------------------------------------------------------------------- hub

  void _hub(Canvas canvas, BoardStyle bs, Offset c, double scale, Color Function(int) armColor) {
    final vertexR = layout.hubRadius / math.cos(math.pi / layout.arms);
    for (var k = 0; k < layout.arms; k++) {
      final th = layout.armAngle(k);
      Offset at(double a, double r) => Offset(
            c.dx + math.sin(a) * r * scale,
            c.dy - math.cos(a) * r * scale,
          );
      final a = at(th - math.pi / layout.arms, vertexR);
      final b = at(th + math.pi / layout.arms, vertexR);
      final col = armColor(k);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = col);
      if (bs.hub == HubStyle.gem) {
        // A lighter facet in every wedge.
        final f = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + (a.dx - c.dx) * 0.62, c.dy + (a.dy - c.dy) * 0.62)
          ..lineTo(c.dx + (b.dx - c.dx) * 0.62, c.dy + (b.dy - c.dy) * 0.62)
          ..close();
        canvas.drawPath(f, Paint()..color = LudoPalette.tint(col, 0.35).withValues(alpha: 0.6));
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale * 0.07
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }

    switch (bs.hub) {
      case HubStyle.wedges:
        canvas.drawCircle(c, scale * 0.42, Paint()..color = bs.hubCenter);
        _star(canvas, c, scale * 0.34, Paint()..color = LudoPalette.gold);
      case HubStyle.gem:
        canvas.drawPath(
          _poly(c, scale * 0.5, 6, math.pi / 6),
          Paint()..color = bs.hubCenter,
        );
        canvas.drawPath(
          _poly(c, scale * 0.5, 6, math.pi / 6),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * 0.06
            ..strokeJoin = StrokeJoin.round
            ..color = LudoPalette.gold,
        );
        _star(canvas, c, scale * 0.32, Paint()..color = LudoPalette.gold);
      case HubStyle.sun:
        canvas.drawCircle(
          c,
          scale * 0.66,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = scale * 0.07
            ..color = Colors.white.withValues(alpha: 0.75),
        );
        canvas.drawCircle(c, scale * 0.46, Paint()..color = bs.hubCenter);
        _star(canvas, c, scale * 0.42, Paint()..color = LudoPalette.gold, points: 12, inner: 0.62);
    }
  }

  // ---------------------------------------------------------------- symbols

  void _mark(Canvas canvas, Offset c, double r, MarkStyle kind, Color color) {
    final paint = Paint()..color = color;
    switch (kind) {
      case MarkStyle.none:
        break;
      case MarkStyle.star:
        _star(canvas, c, r, paint);
      case MarkStyle.diamond:
        canvas.drawPath(_poly(c, r * 1.05, 4, -math.pi / 2), paint);
      case MarkStyle.flower:
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / 5;
          canvas.drawCircle(Offset(c.dx + math.cos(a) * r * 0.55, c.dy + math.sin(a) * r * 0.55), r * 0.44, paint);
        }
        canvas.drawCircle(c, r * 0.3, Paint()..color = LudoPalette.shade(color, 0.28));
      case MarkStyle.ring:
        canvas.drawCircle(
          c,
          r * 0.68,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.3
            ..color = color,
        );
    }
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint, {int points = 5, double inner = 0.45}) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final rr = i.isEven ? r : r * inner;
      final a = -math.pi / 2 + i * math.pi / points;
      final p = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.layout != layout ||
      old.style != style ||
      old.preview != preview ||
      !_sameTeams(old.teamOfArm, teamOfArm);

  static bool _sameTeams(Map<int, int>? a, Map<int, int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Safe-cell highlight for occupied cells.
//
// A token is almost as large as its cell and hides the star printed there.
// While a token stands on a safe cell, this larger gold star is drawn UNDER the
// token, so its points (and a soft glow) stay visible around the token's edge.
// Nothing is drawn on top of the token.
// ---------------------------------------------------------------------------

/// Glow and an oversized star drawn under a token standing on a safe cell.
class SafeCellGlowPainter extends CustomPainter {
  const SafeCellGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            LudoPalette.gold.withValues(alpha: 0.55),
            LudoPalette.gold.withValues(alpha: 0.25),
            LudoPalette.gold.withValues(alpha: 0),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    final star = Path();
    final sr = r * 0.6;
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? sr : sr * 0.5;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    Paint stroke(double w, Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeJoin = StrokeJoin.round
      ..color = col;
    canvas.drawPath(star, stroke(r * 0.16, const Color(0xE6000000)));
    canvas.drawPath(star, stroke(r * 0.08, Colors.white));
    canvas.drawPath(
      star,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF4B0), Color(0xFFFFB300)],
        ).createShader(star.getBounds()),
    );
  }

  @override
  bool shouldRepaint(SafeCellGlowPainter old) => false;
}
