import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import 'ludo_theme.dart';
import 'seat_identity.dart';

/// Winner announcement and final rankings.
class LudoResultsScreen extends ConsumerWidget {
  const LudoResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<LudoUiState>(ludoControllerProvider, (prev, next) {
      final route = ModalRoute.of(context);
      if (route == null) return;
      // Game ended (exit) or was restarted by the host: close this screen.
      if (next.game == null || next.game!.phase != LudoPhase.gameOver) {
        Navigator.of(context).removeRoute(route);
      }
    });

    final ui = ref.watch(ludoControllerProvider);
    final game = ui.game;
    if (game == null) return const Scaffold(body: SizedBox.shrink());
    final ctrl = ref.read(ludoControllerProvider.notifier);
    final standings = LudoEngine.standings(game);
    final canReplay = ui.mode != GameMode.online || (ui.isHost && !ui.quick);
    final theme = Theme.of(context);

    // Is this seat me? See [isMySeat]: online = my own seat; local / vs AI =
    // the only human seat. With several humans on one device nobody is "you".
    bool isMine(int seat) => isMySeat(ui, seat);

    String namesOf(Standing s) => s.seats
        .map((i) => isMine(i) ? '${game.config.seats[i].name} (you)' : game.config.seats[i].name)
        .join(' & ');

    final winner = standings.isEmpty ? null : standings.first;
    final iWon = winner != null && winner.seats.any(isMine);
    final winColor = winner == null
        ? LudoPalette.gold
        : LudoPalette.seat(game.config.layout.colorIndexOfSeat(winner.seats.first));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToMainMenu(context, ctrl);
      },
      child: LudoScaffold(
        title: const Text('Results'),
        automaticallyImplyLeading: false,
        body: Stack(children: [
          const Positioned.fill(child: IgnorePointer(child: _Confetti())),
          SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.2, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.elasticOut,
                    builder: (context, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 130,
                      height: 130,
                      margin: const EdgeInsets.symmetric(horizontal: 100),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [LudoPalette.gold.withValues(alpha: 0.55), Colors.transparent],
                        ),
                      ),
                      child: const Icon(Icons.emoji_events_rounded, size: 92, color: LudoPalette.gold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (winner != null)
                    Text(
                      iWon
                          ? 'You win!'
                          : '${namesOf(winner)} ${winner.seats.length > 1 ? 'win' : 'wins'}!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(color: winColor, blurRadius: 18)],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${game.turnCount} turns · ${game.rollCount} rolls',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  for (final s in standings)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: s.rank == 1
                            ? const BorderSide(color: LudoPalette.gold, width: 2.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: s.rank == 1 ? LudoPalette.gold : theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: s.rank == 1 ? Colors.black87 : Colors.white,
                          child: Text('${s.rank}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        title: Text(namesOf(s), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(_subtitle(game, s)),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            for (final i in s.seats)
                              CircleAvatar(
                                radius: 8,
                                backgroundColor:
                                    LudoPalette.seat(game.config.layout.colorIndexOfSeat(i)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  // const SizedBox(height: 20),
                  // if (canReplay)
                  //   FilledButton.icon(
                  //     style: FilledButton.styleFrom(
                  //       minimumSize: const Size.fromHeight(54),
                  //       backgroundColor: LudoPalette.accent,
                  //       foregroundColor: Colors.white,
                  //     ),
                  //     onPressed: ctrl.restart,
                  //     icon: const Icon(Icons.replay_rounded),
                  //     label: const Text('Play again'),
                  //   ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70, width: 1.5),
                    ),
                    onPressed: () => _backToMainMenu(context, ctrl),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Back to menu'),
                  ),
                ],
              ),
            ),
          ),
          ),
        ]),
      ),
    );
  }

  /// Leaves the game and returns straight to the main (home) screen,
  /// skipping the setup / lobby screens that were opened before the game.
  void _backToMainMenu(BuildContext context, LudoController ctrl) {
    final nav = Navigator.of(context);
    ctrl.exitGame(); // tears the game down; game + results routes remove themselves
    nav.popUntil((route) => route.isFirst);
  }

  String _subtitle(GameState g, Standing s) {
    if (s.seats.every((i) => !g.isActive(i))) {
      return g.presence[s.seats.first] == SeatPresence.left
          ? 'Left the game'
          : 'Removed for inactivity';
    }
    var done = 0;
    for (final seat in s.seats) {
      done += LudoEngine.finishedCount(g, seat);
    }
    final total = s.seats.length * g.config.tokenCount;
    if (done == total) return 'All $total tokens home';
    return '$done of $total tokens home';
  }
}

/// Light falling confetti behind the results.
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final List<_Piece> _pieces = () {
    final r = math.Random(3);
    return List.generate(
      40,
      (_) => _Piece(
        x: r.nextDouble(),
        phase: r.nextDouble(),
        size: 6 + r.nextDouble() * 8,
        color: LudoPalette.seatColors[r.nextInt(LudoPalette.seatColors.length)],
        spin: r.nextDouble() * 6,
      ),
    );
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_pieces, _c.value)),
    );
  }
}

class _Piece {
  _Piece({required this.x, required this.phase, required this.size, required this.color, required this.spin});
  final double x;
  final double phase;
  final double size;
  final Color color;
  final double spin;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final y = ((t + p.phase) % 1.0) * (size.height + 40) - 20;
      final x = p.x * size.width + math.sin((t + p.phase) * math.pi * 4) * 14;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((t + p.phase) * p.spin * math.pi * 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
          const Radius.circular(2),
        ),
        Paint()..color = p.color.withValues(alpha: 0.9),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}