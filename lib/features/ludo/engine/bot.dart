import 'dart:math' as math;

import 'board_layout.dart';
import 'models.dart';
import 'rules_engine.dart';

/// Move selection for computer players.
///
/// easy   - picks any legal move at random.
/// medium - greedy: captures > finishing > entering > safe squares > progress.
/// hard   - medium plus risk awareness: it estimates how exposed a token is to
///          opponents sitting 1-6 cells behind it and avoids / escapes danger.
class LudoBot {
  LudoBot._();

  static LegalMove choose(
    GameState s,
    List<LegalMove> moves,
    BotLevel level,
    math.Random rng,
  ) {
    assert(moves.isNotEmpty);
    if (moves.length == 1) return moves.first;
    if (level == BotLevel.easy) return moves[rng.nextInt(moves.length)];

    var best = moves.first;
    var bestScore = double.negativeInfinity;
    for (final m in moves) {
      final score = _score(s, m, level) + rng.nextDouble() * 0.6;
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return best;
  }

  static double _score(GameState s, LegalMove m, BotLevel level) {
    final layout = s.config.layout;
    final seat = m.token.seat;
    var score = 0.0;

    if (m.captures.isNotEmpty) {
      var victimValue = 0.0;
      for (final c in m.captures) {
        victimValue += s.tokens[c.seat][c.index] + 5;
      }
      score += 55 + victimValue * 0.6;
    }
    if (m.finishes) score += 50;
    if (m.entersBoard) {
      final tokensOut = s.config.tokenCount - LudoEngine.homeCount(s, seat);
      score += tokensOut == 0 ? 60 : 32;
    }

    // An overshoot with "bounce back" enabled: the token walks to home and
    // back by the leftover pips, so it gains little or nothing (and can even
    // lose ground). It must not be treated like real progress.
    final bounced = m.from >= 0 && m.from + s.dice > layout.finishProgress;

    if (bounced) {
      score -= 15; // mostly a wasted move; only taken when nothing is better
    } else if (m.to >= layout.ringSteps && !m.finishes) {
      // Only reward *entering* the private lane (it becomes permanently
      // safe). A token already in the lane is safe, so moving it again is
      // not worth extra.
      if (m.from < layout.ringSteps) score += 22;
    } else if (m.to >= 0 && m.to < layout.ringSteps) {
      if (layout.isSafeCell(layout.ringCell(seat, m.to))) score += 12;
    }

    // Prefer pushing the leader slightly, based on real progress made.
    score += (bounced ? m.from : m.to) * 0.25;

    if (level == BotLevel.hard) {
      final before = _risk(s, seat, m.from, layout);
      final after = _risk(s, seat, m.to, layout);
      score += before * 14; // reward escaping danger
      score -= after * 18; // punish walking into danger
    }
    return score;
  }

  /// Expected exposure of a token of [seat] at [progress]: probability that
  /// some opponent can hit it next turn, scaled by how much progress is lost.
  static double _risk(GameState s, int seat, int progress, BoardLayout layout) {
    if (progress < 0 || progress >= layout.ringSteps) return 0;
    final cell = layout.ringCell(seat, progress);
    if (layout.isSafeCell(cell)) return 0;
    final team = s.config.teams[seat];
    var threats = 0;
    for (var o = 0; o < s.config.playerCount; o++) {
      if (s.config.teams[o] == team) continue;
      for (final p in s.tokens[o]) {
        if (p < 0 || p >= layout.ringSteps) continue;
        final oc = layout.ringCell(o, p);
        final d = (cell - oc + layout.ringLength) % layout.ringLength;
        if (d >= 1 && d <= 6) threats++;
      }
    }
    return (threats / 6.0) * (progress + 5) / 10.0;
  }
}