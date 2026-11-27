import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import 'board_painter.dart';
import 'ludo_style.dart';
import 'ludo_theme.dart';
import 'quick_chat_bubble.dart';
import 'token_painter.dart';

/// Square, resolution-independent board. It fills the largest square that fits
/// its parent, so the same widget works on phones and on resizable Windows
/// windows.
class LudoBoardView extends ConsumerWidget {
  const LudoBoardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only what the board draws. The dice face, banner text and timer
    // change many times a second and must not rebuild the whole board.
    final ui = ref.watch(ludoControllerProvider.select((s) {
      final g = s.game;
      final canPick = g != null &&
          !s.busy &&
          !s.paused &&
          g.phase == LudoPhase.awaitMove &&
          !g.config.seats[g.currentSeat].isBot &&
          (s.mode != GameMode.online || s.mySeat == g.currentSeat);
      return (game: g, shown: s.shown, mode: s.mode, canPick: canPick);
    }));
    final style = ref.watch(ludoStyleProvider);
    final game = ui.game;
    if (game == null) return const SizedBox.shrink();
    final layout = game.config.layout;
    final ctrl = ref.read(ludoControllerProvider.notifier);

    final legal = ui.canPick ? LudoEngine.legalMoves(game) : const <LegalMove>[];
    final movable = {for (final m in legal) m.token};
    final teamMode = game.config.teamMode;
    final teamOfArm = teamMode
        ? <int, int>{
            for (var s = 0; s < game.config.playerCount; s++)
              layout.seatArms[s]: game.config.teams[s],
          }
        : null;

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final side = math.min(box.maxWidth, box.maxHeight);
        final scale = side / (2 * layout.extent);
        final tokenSize = scale * 0.82;
        final half = side / 2;

        // Group tokens that share a cell so they can be fanned out slightly.
        final groups = <String, List<TokenRef>>{};
        for (var s = 0; s < game.config.playerCount; s++) {
          if (!game.isActive(s)) continue; // the player left: no tokens drawn
          for (var i = 0; i < game.config.tokenCount; i++) {
            final p = ui.shown.length > s ? ui.shown[s][i] : game.tokens[s][i];
            if (p == LudoUiState.hiddenToken) continue;
            final pt = layout.tokenPoint(s, i, p);
            final key = '${(pt.x * 100).round()},${(pt.y * 100).round()}';
            groups.putIfAbsent(key, () => []).add(TokenRef(s, i));
          }
        }

        final children = <Widget>[
          // The board itself never changes during a move: keep it in its own
          // layer so gliding tokens do not repaint it every frame.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: BoardPainter(layout, style, false, teamOfArm)),
            ),
          ),
        ];

        // Pulsing landing hints for each legal destination.
        for (final m in legal) {
          final seat = m.token.seat;
          final pt = layout.tokenPoint(seat, m.token.index, m.to);
          children.add(Positioned(
            left: half + pt.x * scale - tokenSize / 2,
            top: half + pt.y * scale - tokenSize / 2,
            width: tokenSize,
            height: tokenSize,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _Pulse(
                  color: m.captures.isNotEmpty ? Colors.redAccent : Colors.white,
                  ring: true,
                ),
              ),
            ),
          ));
        }

        final order = <TokenRef>[
          for (var s = 0; s < game.config.playerCount; s++)
            if (game.isActive(s))
              for (var i = 0; i < game.config.tokenCount; i++)
                if (!(ui.shown.length > s && ui.shown[s][i] == LudoUiState.hiddenToken))
                  TokenRef(s, i),
        ];
        // Draw movable tokens last so they sit on top and receive taps.
        order.sort((a, b) {
          final am = movable.contains(a) ? 1 : 0;
          final bm = movable.contains(b) ? 1 : 0;
          return am.compareTo(bm);
        });

        // Safe cells (stars and start cells) that currently hold a token. The
        // token would hide the printed star, so a larger star is drawn under
        // the token: its points stay visible around the token's edge.
        final litCells = <int>{};
        for (final t in order) {
          final p = ui.shown.length > t.seat ? ui.shown[t.seat][t.index] : game.tokens[t.seat][t.index];
          if (p < 0 || p >= layout.ringSteps) continue; // yard, home lane or finished
          final cell = layout.ringCell(t.seat, p);
          if (layout.isSafeCell(cell)) litCells.add(cell);
        }
        final glowSize = scale * 1.5;
        for (final cell in litCells) {
          final pt = layout.ringPoints[cell];
          children.add(Positioned(
            key: ValueKey('safe_glow_$cell'),
            left: half + pt.x * scale - glowSize / 2,
            top: half + pt.y * scale - glowSize / 2,
            width: glowSize,
            height: glowSize,
            child: const IgnorePointer(
              child: _SafeCellPop(child: CustomPaint(painter: SafeCellGlowPainter())),
            ),
          ));
        }

        for (final ref in order) {
          final p = ui.shown.length > ref.seat ? ui.shown[ref.seat][ref.index] : game.tokens[ref.seat][ref.index];
          final pt = layout.tokenPoint(ref.seat, ref.index, p);
          final key = '${(pt.x * 100).round()},${(pt.y * 100).round()}';
          final group = groups[key]!;
          final n = group.length;
          final slot = group.indexOf(ref);
          var dx = 0.0;
          var dy = 0.0;
          var size = tokenSize;
          if (n > 1 && p >= 0) {
            final a = 2 * math.pi * slot / n;
            dx = math.cos(a) * tokenSize * 0.22;
            dy = math.sin(a) * tokenSize * 0.22;
            size = tokenSize * (n > 3 ? 0.62 : 0.74);
          }
          final isMovable = movable.contains(ref);
          final color = LudoPalette.seat(layout.colorIndexOfSeat(ref.seat));
          children.add(_GlideToken(
            key: ValueKey('t${ref.seat}_${ref.index}'),
            // Linear and a touch longer than one walking step: each new target
            // retargets the glide mid-flight, so a multi-cell move is one
            // continuous motion instead of stop-and-go.
            duration: const Duration(milliseconds: LudoUiState.stepMs + 40),
            left: half + pt.x * scale - size / 2 + dx,
            top: half + pt.y * scale - size / 2 + dy,
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isMovable ? () => ctrl.tokenTapped(ref) : null,
              child: RepaintBoundary(
                child: _TokenPawn(
                  color: color,
                  highlighted: isMovable,
                  style: style.token,
                  cell: Offset(pt.x, pt.y),
                  hopHeight: size * 0.22,
                ),
              ),
            ),
          ));
        }

        // Quick chat bubbles float above everything else, at the senders' yards.
        // Online and Wi-Fi games only; the layer is empty (and free) otherwise.
        if (ui.mode == GameMode.online) {
          children.add(Positioned.fill(
            child: QuickChatBubbleLayer(game: game, side: side, scale: scale),
          ));
        }

        return RepaintBoundary(
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        );
      }),
    );
  }
}

/// Moves its child to a new spot with a linear glide.
///
/// Unlike [AnimatedPositioned] the box is laid out once at its *target* and the
/// glide is a paint-only [Transform], so no layout pass runs on every frame.
/// A new target set mid-glide starts from wherever the token currently is.
class _GlideToken extends StatefulWidget {
  const _GlideToken({
    super.key,
    required this.duration,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.child,
  });
  final Duration duration;
  final double left, top, width, height;
  final Widget child;

  @override
  State<_GlideToken> createState() => _GlideTokenState();
}

class _GlideTokenState extends State<_GlideToken> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration, value: 1);

  /// Remaining distance to the target at t = 0 of the current glide.
  Offset _delta = Offset.zero;

  @override
  void didUpdateWidget(covariant _GlideToken old) {
    super.didUpdateWidget(old);
    final moved = old.left != widget.left || old.top != widget.top;
    if (!moved) return;
    // Where the token is drawn right now, relative to the old target.
    final nowOffset = _delta * (1 - _c.value);
    final visual = Offset(old.left, old.top) + nowOffset;
    _delta = visual - Offset(widget.left, widget.top);
    _c.duration = widget.duration;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) =>
            Transform.translate(offset: _delta * (1 - _c.value), child: child),
      ),
    );
  }
}

class _TokenPawn extends StatefulWidget {
  const _TokenPawn({
    required this.color,
    required this.highlighted,
    required this.style,
    required this.cell,
    required this.hopHeight,
  });
  final Color color;
  final bool highlighted;
  final TokenStyle style;

  /// Board position (in cells); a one-cell change makes the token hop.
  final Offset cell;
  final double hopHeight;

  @override
  State<_TokenPawn> createState() => _TokenPawnState();
}

class _TokenPawnState extends State<_TokenPawn> with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _hop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: LudoUiState.stepMs + 40));

  @override
  void initState() {
    super.initState();
    if (widget.highlighted) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _TokenPawn old) {
    super.didUpdateWidget(old);
    // A normal walking step (about one cell) gets a small hop; long jumps
    // (leaving the yard, being captured) just glide.
    final moved = (widget.cell - old.cell).distance;
    if (moved > 0.01 && moved < 1.6) _hop.forward(from: 0);
    if (widget.highlighted && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.highlighted && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The pawn is painted once (shadow + gradient) in its own layer; the
    // bounce / hop only moves that layer, so a highlighted token no longer
    // repaints every frame while it waits to be picked.
    return AnimatedBuilder(
      animation: Listenable.merge([_c, _hop]),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: TokenPainter(widget.style, widget.color, highlighted: widget.highlighted),
        ),
      ),
      builder: (context, pawn) {
        final bounce = widget.highlighted ? -4.0 * Curves.easeInOut.transform(_c.value) : 0.0;
        final hop = -math.sin(math.pi * _hop.value) * widget.hopHeight;
        return Transform.translate(offset: Offset(0, bounce + hop), child: pawn);
      },
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, this.ring = false});
  final Color color;
  final bool ring;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Transform.scale(
          scale: 0.9 + 0.25 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.18 + 0.18 * t),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.9),
                width: 2.5,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Springy pop-in, played when a token lands on a safe cell so the symbol
/// lights up instead of just appearing.
class _SafeCellPop extends StatelessWidget {
  const _SafeCellPop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      // The token glides in for LudoUiState.stepMs + 40 (= 340 ms), so hold
      // the pop for the first ~45% and let it spring open as the token lands.
      // Cells a token only passes through are gone again before it shows.
      duration: const Duration(milliseconds: 750),
      curve: const Interval(0.45, 1.0, curve: Curves.elasticOut),
      child: child,
      builder: (context, t, child) => Transform.scale(
        scale: 0.35 + 0.65 * t,
        child: Opacity(opacity: t.clamp(0.0, 1.0).toDouble(), child: child),
      ),
    );
  }
}