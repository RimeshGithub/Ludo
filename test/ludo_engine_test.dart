import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/features/ludo/engine/engine.dart';

GameState newGame(int n, {List<int>? teams, bool rankAll = true}) => LudoEngine.newGame(
      GameConfig(
        seats: [for (var i = 0; i < n; i++) SeatConfig(name: 'P$i')],
        teams: teams,
        rankAll: rankAll,
      ),
    );

void main() {
  group('board layouts', () {
    for (var n = 2; n <= 6; n++) {
      test('$n players: dedicated, consistent layout', () {
        final l = BoardLayout.forPlayers(n);
        expect(l.playerCount, n);
        expect(l.seatArms.length, n);
        expect(l.seatArms.toSet().length, n, reason: 'every seat has its own arm');
        expect(l.finishProgress, l.ringSteps + l.laneLength);

        // Every seat walks ringSteps distinct cells, starting on a safe start cell.
        for (var s = 0; s < n; s++) {
          final cells = {for (var p = 0; p < l.ringSteps; p++) l.ringCell(s, p)};
          expect(cells.length, l.ringSteps);
          expect(l.isSafeCell(l.ringCell(s, 0)), isTrue);
          // The last ring cell is the tip of the seat's own arm (home lane entrance).
          expect(l.ringCell(s, l.ringSteps - 1), l.tipCell(l.seatArms[s]));
        }
        expect(l.startCells.length, l.arms);
        expect(l.safeCells.length, greaterThan(l.arms - 1));
      });

      test('$n players: no overlapping cells', () {
        final l = BoardLayout.forPlayers(n);
        final pts = [...l.ringPoints, for (final lane in l.lanePoints) ...lane];
        var min = double.infinity;
        for (var i = 0; i < pts.length; i++) {
          for (var j = i + 1; j < pts.length; j++) {
            min = math.min(min, pts[i].distanceTo(pts[j]));
          }
        }
        expect(min, greaterThan(0.95));
      });
    }

    test('2-4 players share the classic cross; 5 and 6 have their own boards', () {
      for (final n in [2, 3, 4]) {
        final l = BoardLayout.forPlayers(n);
        expect(l.arms, 4);
        expect(l.ringLength, 52);
        expect(l.finishProgress, 56);
        expect(l.name, 'Classic cross');
      }
      expect(BoardLayout.forPlayers(2).seatArms, [0, 2]);
      expect(BoardLayout.forPlayers(3).seatArms, [0, 1, 2]);
      expect(BoardLayout.forPlayers(4).seatArms, [0, 1, 2, 3]);
      expect(BoardLayout.forPlayers(5).arms, 5);
      expect(BoardLayout.forPlayers(6).arms, 6);
      expect(BoardLayout.forPlayers(5).ringLength, isNot(52));
      expect(() => BoardLayout.forPlayers(7), throwsArgumentError);
    });

    test('team presets match their layout', () {
      for (var n = 2; n <= 6; n++) {
        for (final p in BoardLayout.forPlayers(n).teamPresets) {
          expect(p.teamOfSeat.length, n);
        }
      }
      expect(BoardLayout.forPlayers(4).teamPresets, isNotEmpty);
      expect(BoardLayout.forPlayers(6).teamPresets, isNotEmpty);
    });
  });

  group('rules', () {
    test('new game: everything at home', () {
      final s = newGame(4);
      expect(s.tokens.every((t) => t.every((p) => p == -1)), isTrue);
      expect(s.phase, LudoPhase.awaitRoll);
    });

    test('needs a 6 to leave home; otherwise the turn is skipped', () {
      var s = LudoEngine.roll(newGame(4), 3);
      expect(LudoEngine.legalMoves(s), isEmpty);
      s = LudoEngine.passTurn(s);
      expect(s.currentSeat, 1);
      expect(s.phase, LudoPhase.awaitRoll);
    });

    test('a 6 enters the board and grants another roll', () {
      var s = LudoEngine.roll(newGame(4), 6);
      final moves = LudoEngine.legalMoves(s);
      expect(moves.length, 4);
      expect(moves.every((m) => m.entersBoard), isTrue);
      final out = LudoEngine.move(s, const TokenRef(0, 0));
      expect(out.state.tokens[0][0], 0);
      expect(out.state.currentSeat, 0);
      expect(out.state.phase, LudoPhase.awaitRoll);
      expect(out.event.extraTurn, isTrue);
    });

    test('a 1 does nothing special by default', () {
      final s = LudoEngine.roll(newGame(4), 1);
      expect(LudoEngine.legalMoves(s), isEmpty);
      final base = newGame(4);
      base.tokens[0][0] = 5;
      final out = LudoEngine.move(LudoEngine.roll(base, 1), const TokenRef(0, 0));
      expect(out.state.currentSeat, 1);
      expect(out.event.extraTurn, isFalse);
    });

    test('enterOnOne: a 1 brings a token out of the yard', () {
      final cfg = GameConfig(
        seats: [for (var i = 0; i < 4; i++) SeatConfig(name: 'P$i')],
        enterOnOne: true,
      );
      final r = LudoEngine.roll(LudoEngine.newGame(cfg), 1);
      final moves = LudoEngine.legalMoves(r);
      expect(moves.length, 4);
      expect(moves.every((m) => m.entersBoard), isTrue);
      // 2..5 still cannot leave the yard.
      expect(LudoEngine.legalMoves(LudoEngine.roll(LudoEngine.newGame(cfg), 3)), isEmpty);
    });

    test('bonusOnOne: a 1 grants another roll', () {
      final cfg = GameConfig(
        seats: [for (var i = 0; i < 4; i++) SeatConfig(name: 'P$i')],
        bonusOnOne: true,
      );
      final base = LudoEngine.newGame(cfg);
      base.tokens[0][0] = 5;
      final out = LudoEngine.move(LudoEngine.roll(base, 1), const TokenRef(0, 0));
      expect(out.state.currentSeat, 0);
      expect(out.state.phase, LudoPhase.awaitRoll);
      expect(out.event.extraTurn, isTrue);
    });

    test('new rule flags survive a JSON round trip and default to off', () {
      final cfg = GameConfig(
        seats: [for (var i = 0; i < 2; i++) SeatConfig(name: 'P$i')],
        bonusOnOne: true,
        enterOnOne: true,
      );
      final back = GameConfig.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(cfg.toJson())) as Map));
      expect(back.bonusOnOne, isTrue);
      expect(back.enterOnOne, isTrue);
      final plain = GameConfig.fromJson({
        'seats': [
          {'name': 'A', 'kind': 0, 'level': 1},
          {'name': 'B', 'kind': 0, 'level': 1},
        ],
        'teams': [0, 1],
      });
      expect(plain.bonusOnOne, isFalse);
      expect(plain.enterOnOne, isFalse);
    });

    test('exact roll is required to finish', () {
      final base = newGame(4);
      final fin = base.config.layout.finishProgress;
      base.tokens[0][0] = fin - 2;
      expect(LudoEngine.legalMoves(LudoEngine.roll(base, 3)), isEmpty);
      final ok = LudoEngine.roll(base, 2);
      final m = LudoEngine.legalMoves(ok).single;
      expect(m.finishes, isTrue);
      final out = LudoEngine.move(ok, const TokenRef(0, 0));
      expect(out.state.tokens[0][0], fin);
      expect(out.event.reachedFinish, isTrue);
    });

    test('finished tokens cannot move', () {
      final base = newGame(4);
      final fin = base.config.layout.finishProgress;
      base.tokens[0][0] = fin;
      base.tokens[0][1] = 5;
      final r = LudoEngine.roll(base, 2);
      expect(LudoEngine.legalMoves(r).map((m) => m.token), [const TokenRef(0, 1)]);
      expect(() => LudoEngine.move(r, const TokenRef(0, 0)), throwsA(isA<IllegalActionException>()));
    });

    test('landing on an opponent on a normal square captures it', () {
      final base = newGame(4);
      final l = base.config.layout;
      final cell = l.ringCell(0, 3);
      expect(l.isSafeCell(cell), isFalse);
      base.tokens[0][0] = 1;
      base.tokens[1][0] = LudoEngine.progressOnCell(l, 1, cell)!;
      final r = LudoEngine.roll(base, 2);
      expect(LudoEngine.legalMoves(r).single.captures, [const TokenRef(1, 0)]);
      final out = LudoEngine.move(r, const TokenRef(0, 0));
      expect(out.state.tokens[1][0], -1);
      expect(out.state.tokens[0][0], 3);
      expect(out.state.currentSeat, 1);
    });

    test('safe squares protect tokens', () {
      final base = newGame(4);
      final l = base.config.layout;
      final cell = l.ringCell(0, 8);
      expect(l.isSafeCell(cell), isTrue);
      base.tokens[0][0] = 5;
      final oppProgress = LudoEngine.progressOnCell(l, 1, cell)!;
      base.tokens[1][0] = oppProgress;
      final r = LudoEngine.roll(base, 3);
      expect(LudoEngine.legalMoves(r).single.captures, isEmpty);
      final out = LudoEngine.move(r, const TokenRef(0, 0));
      expect(out.state.tokens[1][0], oppProgress);
    });

    test('teammates are never captured', () {
      final base = newGame(4, teams: [0, 1, 0, 1]);
      final l = base.config.layout;
      final cell = l.ringCell(0, 3);
      base.tokens[0][0] = 1;
      base.tokens[2][0] = LudoEngine.progressOnCell(l, 2, cell)!;
      final r = LudoEngine.roll(base, 2);
      expect(LudoEngine.legalMoves(r).single.captures, isEmpty);
    });

    test('in team mode a finished player moves the partner\'s tokens', () {
      final base = newGame(4, teams: [0, 1, 0, 1]);
      final fin = base.config.layout.finishProgress;
      base.tokens[0] = [fin, fin, fin, fin];
      final r = LudoEngine.roll(base, 6);
      final moves = LudoEngine.legalMoves(r);
      expect(moves, isNotEmpty);
      expect(moves.every((m) => m.token.seat == 2), isTrue);
    });

    test('finishing all tokens ranks the player and ends a 2-player game', () {
      final base = newGame(2);
      final fin = base.config.layout.finishProgress;
      base.tokens[0] = [fin, fin, fin, fin - 1];
      final out = LudoEngine.move(LudoEngine.roll(base, 1), const TokenRef(0, 3));
      expect(out.event.teamCompleted, isTrue);
      expect(out.state.phase, LudoPhase.gameOver);
      expect(out.state.ranking, [0, 1]);
      expect(LudoEngine.standings(out.state).first.seats, [0]);
    });

    test('with 3 players the game continues for second place', () {
      final base = newGame(3);
      final fin = base.config.layout.finishProgress;
      base.tokens[0] = [fin, fin, fin, fin - 1];
      final out = LudoEngine.move(LudoEngine.roll(base, 1), const TokenRef(0, 3));
      expect(out.state.phase, LudoPhase.awaitRoll);
      expect(out.state.ranking, [0]);
      expect(out.state.currentSeat, 1);
    });

    test('invalid actions are rejected', () {
      final s = newGame(4);
      expect(() => LudoEngine.move(s, const TokenRef(0, 0)), throwsA(isA<IllegalActionException>()));
      expect(() => LudoEngine.roll(s, 0), throwsA(isA<IllegalActionException>()));
      expect(() => LudoEngine.roll(s, 7), throwsA(isA<IllegalActionException>()));
      final rolled = LudoEngine.roll(s, 6);
      expect(() => LudoEngine.roll(rolled, 3), throwsA(isA<IllegalActionException>()));
      expect(() => LudoEngine.passTurn(rolled), throwsA(isA<IllegalActionException>()));
    });

    test('state survives a JSON round trip', () {
      final s = LudoEngine.roll(newGame(5), 6);
      s.tokens[2][1] = 12;
      final back = GameState.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(s.toJson())) as Map));
      expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
    });
  });

  group('quick start matching', () {
    const base = MatchCriteria(
      playerCount: 4,
      teamPreset: -1,
      bonusOnCapture: false,
      bonusOnFinish: false,
      bonusOnOne: false,
      enterOnOne: false,
      rankAll: true,
    );

    MatchCriteria tweak({
      int? players,
      int? team,
      bool? capture,
      bool? finish,
      bool? one,
      bool? enter,
      bool? rank,
    }) =>
        MatchCriteria(
          playerCount: players ?? base.playerCount,
          teamPreset: team ?? base.teamPreset,
          bonusOnCapture: capture ?? base.bonusOnCapture,
          bonusOnFinish: finish ?? base.bonusOnFinish,
          bonusOnOne: one ?? base.bonusOnOne,
          enterOnOne: enter ?? base.enterOnOne,
          rankAll: rank ?? base.rankAll,
        );

    test('identical criteria match', () {
      expect(tweak().key, base.key);
      expect(tweak(), base);
    });

    test('any single difference prevents a match', () {
      final others = [
        tweak(players: 3),
        tweak(players: 6),
        tweak(team: 0),
        tweak(capture: true),
        tweak(finish: true),
        tweak(one: true),
        tweak(enter: true),
        tweak(rank: false),
      ];
      for (final o in others) {
        expect(o.key, isNot(base.key));
        expect(o == base, isFalse);
      }
      expect(others.map((o) => o.key).toSet().length, others.length);
    });
  });

  group('full games', () {
    GameState play(GameConfig cfg, BotLevel level, int seed) {
      final rng = math.Random(seed);
      var s = LudoEngine.newGame(cfg);
      var guard = 0;
      while (s.phase != LudoPhase.gameOver) {
        expect(guard++, lessThan(60000), reason: 'game did not terminate');
        if (s.phase == LudoPhase.awaitRoll) {
          s = LudoEngine.roll(s, rng.nextInt(6) + 1);
        } else {
          final moves = LudoEngine.legalMoves(s);
          if (moves.isEmpty) {
            s = LudoEngine.passTurn(s);
          } else {
            s = LudoEngine.move(s, LudoBot.choose(s, moves, level, rng).token).state;
          }
        }
        final fin = s.config.layout.finishProgress;
        for (final row in s.tokens) {
          for (final p in row) {
            expect(p, inInclusiveRange(-1, fin));
          }
        }
      }
      return s;
    }

    for (var n = 2; n <= 6; n++) {
      for (final level in BotLevel.values) {
        test('$n players, ${level.name} bots finish a game', () {
          final cfg = GameConfig(seats: [for (var i = 0; i < n; i++) SeatConfig(name: 'B$i')]);
          final s = play(cfg, level, n * 31 + level.index);
          expect(s.ranking.toSet().length, n);
        });
      }
    }

    test('team games finish', () {
      for (final n in [4, 6]) {
        for (final preset in BoardLayout.forPlayers(n).teamPresets) {
          final cfg = GameConfig(
            seats: [for (var i = 0; i < n; i++) SeatConfig(name: 'B$i')],
            teams: preset.teamOfSeat,
          );
          final s = play(cfg, BotLevel.medium, 7 + n);
          expect(s.ranking.toSet().length, preset.teamOfSeat.toSet().length);
        }
      }
    });
  });
}
