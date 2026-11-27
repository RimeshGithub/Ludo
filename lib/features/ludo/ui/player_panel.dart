import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'ludo_theme.dart';

/// Compact card for one seat: colour, name, tokens at home / on board / done.
class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    required this.game,
    required this.seat,
    required this.isCurrent,
    this.isMe = false,
    this.dense = false,
    this.compact = false,
  });

  final GameState game;
  final int seat;
  final bool isCurrent;
  final bool isMe;
  final bool dense;

  /// Narrow grid cell: name on top, counters below, no colour sub-title.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cfg = game.config.seats[seat];
    final layout = game.config.layout;
    final colorIdx = layout.colorIndexOfSeat(seat);
    final color = LudoPalette.seat(colorIdx);
    final home = LudoEngine.homeCount(game, seat);
    final done = LudoEngine.finishedCount(game, seat);
    final out = game.config.tokenCount - home - done;
    final rank = game.ranking.indexOf(game.teamOf(seat));
    final teamNote = game.config.teamMode ? 'Team ${LudoPalette.teamName(game.teamOf(seat))}' : null;
    final away = game.presence[seat];
    final isAway = away != SeatPresence.active;

    if (compact) {
      final sub = [
        if (teamNote != null) teamNote,
      ].join(' · ');
      return Opacity(
        opacity: isAway ? 0.55 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: isCurrent
                ? Color.lerp(LudoPalette.panel, color, 0.38)
                : LudoPalette.panel.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isCurrent ? color : const Color.fromARGB(100, 255, 255, 255), width: 2.5),
            boxShadow: isCurrent
                ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.6),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                    ),
                    child: rank >= 0
                        ? Center(
                            child: Text('${rank + 1}',
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                          )
                        : (cfg.isBot
                            ? const Icon(Icons.smart_toy, size: 11, color: Colors.white)
                            : null),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isMe ? '${cfg.name} (you)' : cfg.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white),
                    ),
                  ),
                ],
              ),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white60)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: isAway
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link_off_rounded, size: 12, color: Colors.redAccent),
                          const SizedBox(width: 3),
                          Text(
                            away == SeatPresence.left ? 'Left' : 'Inactive',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.redAccent),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _stat(context, Icons.home_rounded, home, 'At home: $home'),
                          const SizedBox(width: 7),
                          _stat(context, Icons.directions_run_rounded, out, 'On board: $out'),
                          const SizedBox(width: 7),
                          _stat(context, Icons.flag_rounded, done, 'Finished: $done',
                              highlight: done == game.config.tokenCount),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Opacity(
      opacity: isAway ? 0.55 : 1,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 6 : 8),
      decoration: BoxDecoration(
        color: isCurrent ? Color.lerp(LudoPalette.panel, color, 0.38) : LudoPalette.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isCurrent ? color : const Color.fromARGB(100, 255, 255, 255), width: 2.5),
        boxShadow: isCurrent
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 22 : 28,
            height: dense ? 22 : 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
            ),
            child: rank >= 0
                ? Center(
                    child: Text('${rank + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  )
                : (cfg.isBot
                    ? const Icon(Icons.smart_toy, size: 14, color: Colors.white)
                    : null),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMe ? '${cfg.name} (you)' : cfg.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: dense ? 12.5 : 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  [
                    LudoPalette.name(colorIdx),
                    if (teamNote != null) teamNote,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 10.5, color: Colors.white60),
                ),
                const SizedBox(height: 3),
                if (isAway)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off_rounded, size: 13, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Text(
                        away == SeatPresence.left ? 'Left the game' : 'Inactive',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.redAccent),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _stat(context, Icons.home_rounded, home, 'At home: $home'),
                      const SizedBox(width: 8),
                      _stat(context, Icons.directions_run_rounded, out, 'On board: $out'),
                      const SizedBox(width: 8),
                      _stat(context, Icons.flag_rounded, done, 'Finished: $done', highlight: done == game.config.tokenCount),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, int n, String tip, {bool highlight = false}) {
    return Tooltip(
      message: tip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: highlight ? Colors.amber.shade400 : Colors.white60),
          const SizedBox(width: 2),
          Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}