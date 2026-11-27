import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/quick_chat_catalog.dart';
import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import '../state/quick_chat_controller.dart';
import 'ludo_theme.dart';

/// Draws every active quick chat bubble on top of the board.
///
/// Meant to be a child of the board's square `Stack` (see `LudoBoardView`), whose
/// origin is the board's top-left corner. It watches [quickChatProvider] itself,
/// so a bubble appearing or expiring rebuilds only this layer, not the board.
///
/// Each bubble grows out of the yard of the player who sent it, with its tail
/// pointing at that yard's tokens. Taps pass straight through to the board.
class QuickChatBubbleLayer extends ConsumerWidget {
  const QuickChatBubbleLayer({
    super.key,
    required this.game,
    required this.side,
    required this.scale,
  });

  final GameState game;

  /// Edge length of the board in logical pixels.
  final double side;

  /// Logical pixels per board cell.
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bubbles = ref.watch(quickChatProvider.select((s) => s.bubbles));
    final mySeat = ref.watch(ludoControllerProvider.select((s) => s.mySeat));
    if (bubbles.isEmpty) return const SizedBox.shrink();

    final layout = game.config.layout;
    final half = side / 2;
    // Text size and width follow the yard, so a bubble stays about as wide as
    // the yard it comes from instead of spilling over the track. Longer
    // messages wrap to a second line.
    final fontSize = (scale * 0.5).clamp(10.0, 15.0).toDouble();
    final maxWidth = math.min(side * 0.5, 2 * layout.yardRadius * scale * 1.2);
    final children = <Widget>[];

    for (final e in bubbles.entries) {
      final seat = e.key;
      if (seat < 0 || seat >= game.config.playerCount || !game.isActive(seat)) continue;
      final item = QuickChatCatalog.byId(e.value.itemId);
      if (item == null) continue;

      final yard = layout.yardCenter(layout.seatArms[seat]);
      // Yards in the upper half of the board get their bubble above them (tail
      // pointing down); the others below (tail pointing up). That keeps the
      // bubble in the empty corner of the board instead of over the track.
      final above = yard.y <= 0.5;
      // The tokens sit +-0.34 yard radii from the yard centre; stop just short.
      final reach = layout.yardRadius * 0.34 + 0.2;
      final tip = Offset(
        half + yard.x * scale,
        half + (yard.y + (above ? -reach : reach)) * scale,
      );

      children.add(Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: _BubbleLayout(tip: tip, tailDown: above),
          child: QuickChatBubble(
            // A replacement bubble has a new seq, so it is a new widget and its
            // pop-in animation and lifetime start from zero.
            key: ValueKey('chat_bubble_${e.value.seq}'),
            item: item,
            name: seat == mySeat ? 'You' : game.config.seats[seat].name,
            color: LudoPalette.seat(layout.colorIndexOfSeat(seat)),
            fontSize: fontSize,
            maxWidth: maxWidth,
            tailDown: above,
          ),
        ),
      ));
    }

    return IgnorePointer(
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

/// Puts a bubble so that its tail tip is at [tip], moving it back inside the
/// board when it would stick out.
class _BubbleLayout extends SingleChildLayoutDelegate {
  const _BubbleLayout({required this.tip, required this.tailDown});

  final Offset tip;
  final bool tailDown;

  static const double _margin = 2;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double fit(double v, double extent, double childExtent) {
      final max = math.max(_margin, extent - childExtent - _margin);
      return v.clamp(_margin, max).toDouble();
    }

    final x = fit(tip.dx - childSize.width / 2, size.width, childSize.width);
    final y = fit(tailDown ? tip.dy - childSize.height : tip.dy, size.height, childSize.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) => old.tip != tip || old.tailDown != tailDown;
}

/// One speech bubble. It pops out of its tail tip, stays for
/// [QuickChatConfig.bubbleDuration] and fades away at the end.
class QuickChatBubble extends StatefulWidget {
  const QuickChatBubble({
    super.key,
    required this.item,
    required this.name,
    required this.color,
    required this.fontSize,
    required this.maxWidth,
    required this.tailDown,
    this.lifetime = QuickChatConfig.bubbleDuration,
  });

  final QuickChatItem item;

  /// Sender's name shown above the message ("You" on the sender's own device).
  final String name;

  /// Border colour (the sender's seat colour).
  final Color color;
  final double fontSize;
  final double maxWidth;

  /// True: the tail is below the body (bubble sits above its yard).
  final bool tailDown;

  /// Total time on screen, including the pop-in and the fade-out.
  final Duration lifetime;

  @override
  State<QuickChatBubble> createState() => _QuickChatBubbleState();
}

class _QuickChatBubbleState extends State<QuickChatBubble> with SingleTickerProviderStateMixin {
  static const double _popMs = 260;
  static const double _fadeInMs = 100;
  static const double _fadeOutMs = 400;

  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.lifetime)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lifeMs = widget.lifetime.inMilliseconds.toDouble();
    return AnimatedBuilder(
      animation: _c,
      child: _body(),
      builder: (context, child) {
        final ms = _c.value * lifeMs;
        final pop = Curves.easeOutBack.transform((ms / _popMs).clamp(0.0, 1.0).toDouble());
        final fadeIn = (ms / _fadeInMs).clamp(0.0, 1.0).toDouble();
        final fadeOut = ((lifeMs - ms) / _fadeOutMs).clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: math.min(fadeIn, fadeOut),
          child: Transform.scale(
            scale: 0.3 + 0.7 * pop,
            // Grow out of the tail tip, i.e. out of the yard.
            alignment: widget.tailDown ? Alignment.bottomCenter : Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }

  Widget _body() {
    final f = widget.fontSize;
    final item = widget.item;
    final tailH = f * 0.7;
    final emojiOnly = item.text == null;

    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.emoji != null)
          Text(
            item.emoji!,
            style: TextStyle(fontSize: emojiOnly ? f * 2.0 : f * 1.3, height: 1.1),
          ),
        if (item.emoji != null && item.text != null) SizedBox(width: f * 0.4),
        if (item.text != null)
          Flexible(
            child: Text(
              item.text!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF1B1633),
                fontSize: f,
                fontWeight: FontWeight.w800,
                height: 1.1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
      ],
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: LudoPalette.shade(widget.color, 0.35),
            fontSize: f * 0.8,
            fontWeight: FontWeight.w800,
            height: 1.1,
            decoration: TextDecoration.none,
          ),
        ),
        SizedBox(height: f * 0.15),
        line,
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: CustomPaint(
        painter: _BubblePainter(
          color: widget.color,
          tailDown: widget.tailDown,
          tailH: tailH,
          tailW: f,
          radius: f * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            f * 0.6,
            f * 0.35 + (widget.tailDown ? 0 : tailH),
            f * 0.6,
            f * 0.35 + (widget.tailDown ? tailH : 0),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Rounded rectangle with a centred tail, filled and outlined as one shape so
/// the outline runs unbroken where the tail joins the body.
class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.color,
    required this.tailDown,
    required this.tailH,
    required this.tailW,
    required this.radius,
  });

  final Color color;
  final bool tailDown;
  final double tailH;
  final double tailW;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyTop = tailDown ? 0.0 : tailH;
    final bodyBottom = tailDown ? size.height - tailH : size.height;
    final body = RRect.fromLTRBR(0, bodyTop, size.width, bodyBottom, Radius.circular(radius));

    final cx = size.width / 2;
    // The tail overlaps the body by a pixel so the union is a single outline.
    final tail = Path();
    if (tailDown) {
      tail
        ..moveTo(cx - tailW / 2, bodyBottom - 1)
        ..lineTo(cx, size.height)
        ..lineTo(cx + tailW / 2, bodyBottom - 1);
    } else {
      tail
        ..moveTo(cx - tailW / 2, bodyTop + 1)
        ..lineTo(cx, 0)
        ..lineTo(cx + tailW / 2, bodyTop + 1);
    }
    tail.close();

    final shape = Path.combine(PathOperation.union, Path()..addRRect(body), tail);
    canvas.drawShadow(shape, Colors.black, 3, true);
    canvas.drawPath(shape, Paint()..color = Colors.white);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.color != color ||
      old.tailDown != tailDown ||
      old.tailH != tailH ||
      old.tailW != tailW ||
      old.radius != radius;
}