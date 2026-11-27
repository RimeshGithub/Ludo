import 'dart:async';

import 'package:flutter/material.dart';

/// Countdown for the current move (online games).
///
/// [deadlineMs] is the moment the move expires on *this device's* clock; the
/// controller has already converted the host's shared server-clock deadline,
/// so every player's bar drains in step. The widget only draws: it re-reads
/// the clock ten times a second and never owns any game logic.
class TurnTimer extends StatefulWidget {
  const TurnTimer({
    super.key,
    required this.deadlineMs,
    required this.limitMs,
    required this.color,
  });

  final int deadlineMs;
  final int limitMs;
  final Color color;

  @override
  State<TurnTimer> createState() => _TurnTimerState();
}

class _TurnTimerState extends State<TurnTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final limit = widget.limitMs <= 0 ? 1 : widget.limitMs;
    final left =
        (widget.deadlineMs - DateTime.now().millisecondsSinceEpoch).clamp(0, limit).toInt();
    final fraction = left / limit;
    final seconds = (left / 1000).ceil();
    final urgent = left <= 10000;
    final critical = left <= 5000;
    final barColor = critical
        ? Colors.redAccent
        : urgent
            ? Colors.amber
            : widget.color;

    return Semantics(
      label: 'Time left for this move: $seconds seconds',
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 16, color: barColor),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '${seconds}s',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: barColor,
                fontWeight: FontWeight.w800,
                fontSize: critical ? 16 : 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
