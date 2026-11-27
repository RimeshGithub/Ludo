import 'board_layout.dart';
import 'models.dart';

class IllegalActionException implements Exception {
  final String message;
  IllegalActionException(this.message);
  @override
  String toString() => 'IllegalActionException: $message';
}

/// One validated move available for the dice value currently on the table.
class LegalMove {
  final TokenRef token;
  final int from;
  final int to;
  final bool entersBoard;
  final bool finishes;
  final List<TokenRef> captures;

  const LegalMove({
    required this.token,
    required this.from,
    required this.to,
    required this.entersBoard,
    required this.finishes,
    this.captures = const [],
  });
}

/// What happened when a move was applied (used for sounds / messages).
class MoveEvent {
  final int actor;
  final TokenRef token;
  final int from;
  final int to;
  final int dice;
  final List<TokenRef> captured;
  final bool entersBoard;
  final bool reachedFinish;
  final bool teamCompleted;
  final bool extraTurn;
  final bool gameOver;

  const MoveEvent({
    required this.actor,
    required this.token,
    required this.from,
    required this.to,
    required this.dice,
    required this.captured,
    required this.entersBoard,
    required this.reachedFinish,
    required this.teamCompleted,
    required this.extraTurn,
    required this.gameOver,
  });
}

class MoveOutcome {
  final GameState state;
  final MoveEvent event;
  const MoveOutcome(this.state, this.event);
}

class Standing {
  final int rank;
  final int team;
  final List<int> seats;
  const Standing(this.rank, this.team, this.seats);
}

/// Pure rules engine. No Flutter, no I/O, no randomness: dice values are
/// passed in, which keeps every transition deterministic and testable.
/// Every public method validates its input and throws
/// [IllegalActionException] instead of producing an invalid state.
class LudoEngine {
  LudoEngine._();

  /// Consecutive turn timeouts after which a player is removed (online).
  static const int maxMissedTurns = 3;

  static GameState newGame(GameConfig config, {int startSeat = 0}) {
    if (startSeat < 0 || startSeat >= config.playerCount) {
      throw ArgumentError.value(startSeat, 'startSeat');
    }
    return GameState(
      config: config,
      // With "One Token Out" the first token of every seat starts on its
      // start square (progress 0) instead of in the yard.
      tokens: List.generate(
        config.playerCount,
        (_) => List<int>.generate(
            config.tokenCount, (i) => config.oneTokenOut && i == 0 ? 0 : -1),
      ),
      currentSeat: startSeat,
      phase: LudoPhase.awaitRoll,
      dice: 0,
      rollCount: 0,
      turnCount: 1,
      ranking: [],
    );
  }

  // ----------------------------------------------------------------- queries

  static bool isTokenDone(GameState s, int seat, int index) =>
      s.tokens[seat][index] >= s.config.layout.finishProgress;

  /// A seat that left or went inactive has no tokens and counts as done, so
  /// it never blocks its team from finishing.
  static bool isSeatDone(GameState s, int seat) {
    if (!s.isActive(seat)) return true;
    for (var i = 0; i < s.config.tokenCount; i++) {
      if (!isTokenDone(s, seat, i)) return false;
    }
    return true;
  }

  static bool isTeamDone(GameState s, int team) {
    for (var seat = 0; seat < s.config.playerCount; seat++) {
      if (s.config.teams[seat] == team && !isSeatDone(s, seat)) return false;
    }
    return true;
  }

  static int homeCount(GameState s, int seat) =>
      s.tokens[seat].where((p) => p < 0).length;

  static int finishedCount(GameState s, int seat) =>
      s.tokens[seat].where((p) => p >= s.config.layout.finishProgress).length;

  static int onBoardCount(GameState s, int seat) =>
      s.config.tokenCount - homeCount(s, seat) - finishedCount(s, seat);

  static List<TokenRef> _unfinished(GameState s, int seat) => [
        if (s.isActive(seat))
          for (var i = 0; i < s.config.tokenCount; i++)
            if (!isTokenDone(s, seat, i)) TokenRef(seat, i),
      ];

  /// Tokens [seat] may move on its turn: its own unfinished tokens, or - in
  /// team games, once all of its own tokens are home - its partners' tokens.
  static List<TokenRef> actingTokens(GameState s, int seat) {
    if (!s.isActive(seat)) return const [];
    final own = _unfinished(s, seat);
    if (own.isNotEmpty) return own;
    final res = <TokenRef>[];
    for (var mate = 0; mate < s.config.playerCount; mate++) {
      if (mate != seat && s.config.teams[mate] == s.config.teams[seat]) {
        res.addAll(_unfinished(s, mate));
      }
    }
    return res;
  }

  static List<TokenRef> _capturesAt(GameState s, int seat, int to) {
    final layout = s.config.layout;
    if (to < 0 || to >= layout.ringSteps) return const [];
    final cell = layout.ringCell(seat, to);
    if (layout.isSafeCell(cell)) return const [];
    final team = s.config.teams[seat];
    final hit = <TokenRef>[];
    for (var o = 0; o < s.config.playerCount; o++) {
      if (s.config.teams[o] == team) continue;
      for (var i = 0; i < s.config.tokenCount; i++) {
        final p = s.tokens[o][i];
        if (p >= 0 && p < layout.ringSteps && layout.ringCell(o, p) == cell) {
          hit.add(TokenRef(o, i));
        }
      }
    }
    // Without stacked capture, two or more opponent tokens on a square form a
    // stack that cannot be captured.
    if (!s.config.stackedCapture && hit.length >= 2) return const [];
    return hit;
  }

  /// All legal moves for the dice value on the table (empty unless the phase
  /// is [LudoPhase.awaitMove]).
  static List<LegalMove> legalMoves(GameState s) {
    if (s.phase != LudoPhase.awaitMove) return const [];
    if (isSixesForfeit(s)) return const [];
    final layout = s.config.layout;
    final d = s.dice;
    final out = <LegalMove>[];
    for (final ref in actingTokens(s, s.currentSeat)) {
      final p = s.tokens[ref.seat][ref.index];
      final int to;
      if (p < 0) {
        // A six leaves the yard; a one does too when the rule is enabled.
        if (d != 6 && !(s.config.enterOnOne && d == 1)) continue;
        to = 0;
      } else {
        var target = p + d;
        if (target > layout.finishProgress) {
          if (!s.config.bounceBack) continue; // exact roll to finish
          // Overshoot: walk to home, then back by the leftover pips.
          target = 2 * layout.finishProgress - target;
        }
        to = target;
      }
      out.add(LegalMove(
        token: ref,
        from: p,
        to: to,
        entersBoard: p < 0,
        finishes: to == layout.finishProgress,
        captures: _capturesAt(s, ref.seat, to),
      ));
    }
    return out;
  }

  // ----------------------------------------------------------------- actions

  static bool canRoll(GameState s) => s.phase == LudoPhase.awaitRoll;

  /// True when the roll on the table is a forfeited third 6 in a row.
  static bool isSixesForfeit(GameState s) =>
      s.config.threeSixesForfeit &&
      s.phase == LudoPhase.awaitMove &&
      s.dice == 6 &&
      s.sixStreak >= 3;

  /// Registers a dice [value] (1..6) for the current seat.
  static GameState roll(GameState s, int value) {
    if (s.phase != LudoPhase.awaitRoll) {
      throw IllegalActionException('The game is not waiting for a roll');
    }
    if (value < 1 || value > 6) {
      throw IllegalActionException('Dice value must be 1..6, got $value');
    }
    final n = s.copy();
    n.dice = value;
    n.rollCount += 1;
    n.sixStreak = value == 6 ? s.sixStreak + 1 : 0;
    n.phase = LudoPhase.awaitMove;
    return n;
  }

  /// Ends the turn when the roll offers no legal move.
  static GameState passTurn(GameState s) {
    if (s.phase != LudoPhase.awaitMove) {
      throw IllegalActionException('Nothing to pass');
    }
    if (legalMoves(s).isNotEmpty) {
      throw IllegalActionException('A legal move exists; the turn cannot be skipped');
    }
    final n = s.copy();
    n.missed[s.currentSeat] = 0; // the player rolled, so they are present
    _advance(n);
    return n;
  }

  /// Ends the turn of a player who never rolled (time ran out). No extra roll.
  /// Counts as a missed turn; after [maxMissedTurns] in a row the seat is
  /// removed from the game.
  static GameState skipRoll(GameState s) {
    if (s.phase != LudoPhase.awaitRoll) {
      throw IllegalActionException('Nothing to skip');
    }
    final n = s.copy();
    final seat = n.currentSeat;
    n.missed[seat] += 1;
    if (n.missed[seat] >= maxMissedTurns) {
      _removeSeatIn(n, seat, SeatPresence.inactive);
    } else {
      _advance(n);
    }
    return n;
  }

  /// Takes [seat] out of the game: its tokens vanish from the board, the seat
  /// is marked [reason] and skipped from now on. If that leaves a single
  /// team in play the game ends. Does nothing for a seat that is already out.
  static GameState removeSeat(GameState s, int seat, SeatPresence reason) {
    if (seat < 0 || seat >= s.config.playerCount) {
      throw ArgumentError.value(seat, 'seat');
    }
    if (reason == SeatPresence.active) {
      throw ArgumentError.value(reason, 'reason', 'must not be active');
    }
    final n = s.copy();
    _removeSeatIn(n, seat, reason);
    return n;
  }

  /// Moves [ref] by the rolled value, resolving captures, finishing, rankings
  /// and whose turn comes next.
  ///
  /// [auto] marks a move played for the player because their time ran out:
  /// it counts as a missed turn (and may remove the seat), whereas a move the
  /// player made themselves resets their missed-turn counter.
  static MoveOutcome move(GameState s, TokenRef ref, {bool auto = false}) {
    if (s.phase != LudoPhase.awaitMove) {
      throw IllegalActionException('The game is not waiting for a move');
    }
    LegalMove? chosen;
    for (final m in legalMoves(s)) {
      if (m.token == ref) {
        chosen = m;
        break;
      }
    }
    if (chosen == null) {
      throw IllegalActionException('$ref cannot move ${s.dice}');
    }

    final n = s.copy();
    final layout = n.config.layout;
    final actor = s.currentSeat;
    final team = n.config.teams[actor];

    n.tokens[ref.seat][ref.index] = chosen.to;
    for (final c in chosen.captures) {
      n.tokens[c.seat][c.index] = -1;
    }

    var teamCompleted = false;
    if (isTeamDone(n, team) && !n.ranking.contains(team)) {
      n.ranking.add(team);
      teamCompleted = true;
    }

    final activeTeams = _activeTeams(n);
    final over = n.config.rankAll ? activeTeams.length <= 1 : n.ranking.isNotEmpty;

    final extra = n.dice == 6 ||
        (n.dice == 1 && n.config.bonusOnOne) ||
        (chosen.captures.isNotEmpty && n.config.bonusOnCapture) ||
        (chosen.finishes && n.config.bonusOnFinish);

    if (over) {
      _finishRanking(n);
    } else if (teamCompleted || !extra) {
      _advance(n);
    } else {
      n.phase = LudoPhase.awaitRoll; // same seat rolls again
    }

    if (auto) {
      n.missed[actor] += 1;
      if (!over && n.missed[actor] >= maxMissedTurns) {
        _removeSeatIn(n, actor, SeatPresence.inactive);
      }
    } else {
      n.missed[actor] = 0;
    }

    return MoveOutcome(
      n,
      MoveEvent(
        actor: actor,
        token: ref,
        from: chosen.from,
        to: chosen.to,
        dice: s.dice,
        captured: chosen.captures,
        entersBoard: chosen.entersBoard,
        reachedFinish: chosen.to == layout.finishProgress,
        teamCompleted: teamCompleted,
        extraTurn: !over && !teamCompleted && extra,
        gameOver: over,
      ),
    );
  }

  // ---------------------------------------------------------------- internals

  static List<int> _activeTeams(GameState n) {
    final out = <int>[];
    for (final t in n.config.teams.toSet()) {
      if (!isTeamDone(n, t)) out.add(t);
    }
    return out;
  }

  static int _teamProgress(GameState n, int team) {
    var sum = 0;
    for (var seat = 0; seat < n.config.playerCount; seat++) {
      if (n.config.teams[seat] != team) continue;
      for (final p in n.tokens[seat]) {
        if (p > 0) sum += p;
      }
    }
    return sum;
  }

  static bool _teamHasActiveSeat(GameState n, int team) {
    for (var seat = 0; seat < n.config.playerCount; seat++) {
      if (n.config.teams[seat] == team && n.isActive(seat)) return true;
    }
    return false;
  }

  static void _finishRanking(GameState n) {
    // Teams still in play are ranked by progress; teams whose players all
    // left or went inactive come last.
    final playing = <int>[];
    final abandoned = <int>[];
    for (final t in n.config.teams.toSet()) {
      if (n.ranking.contains(t)) continue;
      (_teamHasActiveSeat(n, t) ? playing : abandoned).add(t);
    }
    playing.sort((a, b) => _teamProgress(n, b).compareTo(_teamProgress(n, a)));
    abandoned.sort();
    n.ranking.addAll(playing);
    n.ranking.addAll(abandoned);
    n.phase = LudoPhase.gameOver;
  }

  static void _removeSeatIn(GameState n, int seat, SeatPresence reason) {
    if (n.phase == LudoPhase.gameOver || !n.isActive(seat)) return;
    n.presence[seat] = reason;
    n.missed[seat] = 0;
    for (var i = 0; i < n.config.tokenCount; i++) {
      n.tokens[seat][i] = -1;
    }
    // A team whose remaining players have all finished is complete now that
    // their partner is gone.
    for (final t in n.config.teams.toSet()) {
      if (!n.ranking.contains(t) && isTeamDone(n, t) && _teamHasActiveSeat(n, t)) {
        n.ranking.add(t);
      }
    }
    final inPlay = _activeTeams(n);
    final over = inPlay.length <= 1 || (!n.config.rankAll && n.ranking.isNotEmpty);
    if (over) {
      _finishRanking(n);
    } else if (n.currentSeat == seat) {
      _advance(n);
    }
  }

  static void _advance(GameState n) {
    final count = n.config.playerCount;
    for (var i = 1; i <= count; i++) {
      final seat = (n.currentSeat + i) % count;
      if (n.isActive(seat) && !isTeamDone(n, n.config.teams[seat])) {
        n.currentSeat = seat;
        n.phase = LudoPhase.awaitRoll;
        n.sixStreak = 0;
        n.turnCount += 1;
        return;
      }
    }
    _finishRanking(n);
  }

  /// Final / current standings, best first.
  static List<Standing> standings(GameState s) {
    final out = <Standing>[];
    for (var i = 0; i < s.ranking.length; i++) {
      final team = s.ranking[i];
      out.add(Standing(i + 1, team, [
        for (var seat = 0; seat < s.config.playerCount; seat++)
          if (s.config.teams[seat] == team) seat,
      ]));
    }
    return out;
  }

  /// Used by tests and the UI to find how far a seat has to go.
  static int stepsToFinish(GameState s, int seat) {
    final layout = s.config.layout;
    var total = 0;
    for (final p in s.tokens[seat]) {
      total += layout.finishProgress - (p < 0 ? -1 : p);
    }
    return total;
  }

  /// Convenience for tests: progress of [seat] that sits on ring [cell].
  static int? progressOnCell(BoardLayout layout, int seat, int cell) {
    for (var p = 0; p < layout.ringSteps; p++) {
      if (layout.ringCell(seat, p) == cell) return p;
    }
    return null;
  }
}
