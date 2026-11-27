import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ludo_style.dart';
import 'ludo_theme.dart';

/// Draws one token in the chosen [TokenStyle]. Used on the board and in the
/// theme picker preview.
class TokenPainter extends CustomPainter {
  TokenPainter(this.style, this.color, {this.highlighted = false});
  final TokenStyle style;
  final Color color;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case TokenStyle.ball:
        _ball(canvas, size);
      case TokenStyle.pawn:
        _pawn(canvas, size);
      case TokenStyle.gem:
        _gem(canvas, size);
      case TokenStyle.ring:
        _ring(canvas, size);
    }
  }

  Paint _grad(Offset c, double r) => Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.35, -0.4),
      colors: [LudoPalette.tint(color, 0.45), color, LudoPalette.shade(color, 0.3)],
      stops: const [0, 0.55, 1],
    ).createShader(Rect.fromCircle(center: c, radius: r));

  Paint get _outline => Paint()
    ..style = PaintingStyle.stroke
    ..color = highlighted ? Colors.white : Colors.white.withValues(alpha: 0.9);

  void _hint(Canvas canvas, Offset c, double r) {
    if (!highlighted) return;
    canvas.drawCircle(
      c,
      r * 1.05,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..color = Colors.black87,
    );
  }

  void _ball(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, size.height / 2);
    canvas.drawCircle(c.translate(0, r * 0.14), r * 0.92, Paint()..color = Colors.black.withValues(alpha: 0.28));
    canvas.drawCircle(c, r * 0.92, _grad(c, r));
    canvas.drawCircle(c, r * 0.92, _outline..strokeWidth = r * (highlighted ? 0.22 : 0.12));
    _hint(canvas, c, r);
    canvas.drawCircle(c, r * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  void _pawn(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w / 2;
    final cx = w / 2;
    final path = Path()
      // base
      ..moveTo(cx - w * 0.42, h * 0.92)
      ..quadraticBezierTo(cx - w * 0.44, h * 0.78, cx - w * 0.2, h * 0.74)
      // neck
      ..quadraticBezierTo(cx - w * 0.1, h * 0.55, cx - w * 0.14, h * 0.46)
      ..lineTo(cx + w * 0.14, h * 0.46)
      ..quadraticBezierTo(cx + w * 0.1, h * 0.55, cx + w * 0.2, h * 0.74)
      ..quadraticBezierTo(cx + w * 0.44, h * 0.78, cx + w * 0.42, h * 0.92)
      ..close();
    final headC = Offset(cx, h * 0.30);
    final headR = w * 0.24;
    canvas.drawShadow(path, Colors.black, 3, true);
    final body = Paint()
      ..shader = LinearGradient(
        colors: [LudoPalette.tint(color, 0.35), color, LudoPalette.shade(color, 0.3)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(path, body);
    canvas.drawCircle(headC, headR, _grad(headC, headR));
    final o = _outline..strokeWidth = r * (highlighted ? 0.16 : 0.09);
    canvas.drawPath(path, o);
    canvas.drawCircle(headC, headR, o);
    if (highlighted) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..color = Colors.black87,
      );
    }
  }

  void _gem(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, size.height / 2);
    final pts = <Offset>[
      for (var i = 0; i < 6; i++)
        Offset(c.dx + math.cos(i * math.pi / 3 - math.pi / 2) * r * 0.9,
            c.dy + math.sin(i * math.pi / 3 - math.pi / 2) * r * 0.9),
    ];
    final hex = Path()..addPolygon(pts, true);
    canvas.drawShadow(hex, Colors.black, 3, true);
    canvas.drawPath(hex, Paint()..color = color);
    // facets
    final tops = [pts[0], pts[1], c];
    final left = [pts[0], pts[5], c];
    final bottom = [pts[2], pts[3], c];
    canvas.drawPath(Path()..addPolygon(tops, true), Paint()..color = LudoPalette.tint(color, 0.35));
    canvas.drawPath(Path()..addPolygon(left, true), Paint()..color = LudoPalette.tint(color, 0.55));
    canvas.drawPath(Path()..addPolygon(bottom, true), Paint()..color = LudoPalette.shade(color, 0.3));
    canvas.drawPath(hex, _outline..strokeWidth = r * (highlighted ? 0.2 : 0.1)..strokeJoin = StrokeJoin.round);
    if (highlighted) {
      canvas.drawPath(
        hex,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.07
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black87,
      );
    }
  }

  void _ring(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, size.height / 2);
    canvas.drawCircle(c.translate(0, r * 0.12), r * 0.88, Paint()..color = Colors.black.withValues(alpha: 0.25));
    canvas.drawCircle(c, r * 0.88, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.52
        ..color = color,
    );
    canvas.drawCircle(c, r * 0.3, Paint()..color = LudoPalette.shade(color, 0.15));
    canvas.drawCircle(
      c,
      r * 0.88,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * (highlighted ? 0.16 : 0.07)
        ..color = highlighted ? Colors.black87 : LudoPalette.shade(color, 0.35),
    );
  }

  @override
  bool shouldRepaint(TokenPainter old) =>
      old.style != style || old.color != color || old.highlighted != highlighted;
}
