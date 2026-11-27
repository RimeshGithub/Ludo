import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/features/ludo/engine/engine.dart';

GameConfig cfg(int n, {List<int>? teams, bool rankAll = true}) => GameConfig(
    seats: [for (var i = 0; i < n; i++) SeatConfig(name: 'P$i', uid: 'u$i')],
    teams: teams,
    rankAll: rankAll);

void main() {
  group('timeouts', () {
    test('three consecutive missed turns remove the seat', () {
      var s = LudoEngine.newGame(cfg(4));
      s.tokens[0][0] = 5;
      s = LudoEngine.skipRoll(s);
      expect(s.missed[0], 1);
      expect(s.currentSeat, 1);
      s.currentSeat = 0;
      s = LudoEngine.skipRoll(s);
      expect(s.missed[0], 2);
      expect(s.isActive(0), isTrue);
      s.currentSeat = 0;
      s = LudoEngine.skipRoll(s);
      expect(s.presence[0], SeatPresence.inactive);
      expect(s.tokens[0].every((p) => p == -1), isTrue);
      expect(s.currentSeat, isNot(0));
      expect(s.phase, LudoPhase.awaitRoll);
    });

    test('a manual move resets the counter, an automatic move counts', () {
      var s = LudoEngine.newGame(cfg(4))..missed[0] = 2;
      var r = LudoEngine.roll(s, 6);
      final manual = LudoEngine.move(r, LudoEngine.legalMoves(r).first.token);
      expect(manual.state.missed[0], 0);
      expect(manual.state.isActive(0), isTrue);

      s = LudoEngine.newGame(cfg(4))..missed[0] = 2;
      r = LudoEngine.roll(s, 6);
      final auto =
          LudoEngine.move(r, LudoEngine.legalMoves(r).first.token, auto: true);
      expect(auto.state.presence[0], SeatPresence.inactive);
      expect(auto.state.tokens[0].every((p) => p == -1), isTrue);
      expect(auto.state.currentSeat, isNot(0));
    });

    test('passing after the player rolled resets the counter', () {
      final s = LudoEngine.newGame(cfg(4))..missed[0] = 2;
      final r = LudoEngine.roll(s, 3);
      expect(LudoEngine.passTurn(r).missed[0], 0);
    });
  });

  group('leaving', () {
    test('tokens vanish, seat is marked left and skipped', () {
      final s = LudoEngine.newGame(cfg(4));
      s.tokens[2][1] = 9;
      s.currentSeat = 2;
      final l = LudoEngine.removeSeat(s, 2, SeatPresence.left);
      expect(l.presence[2], SeatPresence.left);
      expect(l.tokens[2].every((p) => p == -1), isTrue);
      expect(l.currentSeat, 3);
      expect(LudoEngine.actingTokens(l, 2), isEmpty);
    });

    test('last team standing wins; leavers rank last', () {
      var s = LudoEngine.newGame(cfg(2));
      var l = LudoEngine.removeSeat(s, 0, SeatPresence.left);
      expect(l.phase, LudoPhase.gameOver);
      expect(l.ranking, [1, 0]);

      s = LudoEngine.newGame(cfg(4));
      l = LudoEngine.removeSeat(s, 0, SeatPresence.left);
      l = LudoEngine.removeSeat(l, 1, SeatPresence.inactive);
      expect(l.phase, isNot(LudoPhase.gameOver));
      l = LudoEngine.removeSeat(l, 2, SeatPresence.left);
      expect(l.phase, LudoPhase.gameOver);
      expect(l.ranking.first, 3);
      expect(l.ranking.toSet().length, 4);
    });

    test('team games: partner leaves, team plays on; both leave, other team wins', () {
      const teams = [0, 1, 0, 1];
      var s = LudoEngine.newGame(cfg(4, teams: teams));
      var l = LudoEngine.removeSeat(s, 0, SeatPresence.left);
      expect(l.phase, isNot(LudoPhase.gameOver));
      l = LudoEngine.removeSeat(l, 2, SeatPresence.left);
      expect(l.phase, LudoPhase.gameOver);
      expect(l.ranking.first, 1);

      s = LudoEngine.newGame(cfg(4, teams: teams));
      s.tokens[0].fillRange(0, 4, s.config.layout.finishProgress);
      s.currentSeat = 1;
      l = LudoEngine.removeSeat(s, 2, SeatPresence.left);
      expect(l.ranking, contains(0));
    });
  });

  group('serialisation', () {
    test('presence round-trips and old saves still load', () {
      var s = LudoEngine.newGame(cfg(3))..missed[1] = 2;
      s = LudoEngine.removeSeat(s, 2, SeatPresence.inactive);
      final j = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
      final back = GameState.fromJson(j);
      expect(back.presence[2], SeatPresence.inactive);
      expect(back.missed[1], 2);
      j.remove('presence');
      j.remove('missed');
      final old = GameState.fromJson(j);
      expect(old.presence.every((p) => p == SeatPresence.active), isTrue);
    });
  });

  test('random games with departures and timeouts always finish cleanly', () {
    final rng = Random(7);
    for (var g = 0; g < 300; g++) {
      final n = 2 + rng.nextInt(5);
      List<int>? teams;
      final presets = BoardLayout.forPlayers(n).teamPresets;
      if (presets.isNotEmpty && rng.nextBool()) {
        teams = presets[rng.nextInt(presets.length)].teamOfSeat;
      }
      var st = LudoEngine.newGame(cfg(n, teams: teams, rankAll: rng.nextBool()));
      for (var step = 0; step < 6000 && st.phase != LudoPhase.gameOver; step++) {
        final act = rng.nextInt(100);
        if (act < 2) {
          st = LudoEngine.removeSeat(st, rng.nextInt(n), SeatPresence.left);
        } else if (act < 8 && st.phase == LudoPhase.awaitRoll) {
          st = LudoEngine.skipRoll(st);
        } else if (st.phase == LudoPhase.awaitRoll) {
          st = LudoEngine.roll(st, 1 + rng.nextInt(6));
        } else {
          final mv = LudoEngine.legalMoves(st);
          st = mv.isEmpty
              ? LudoEngine.passTurn(st)
              : LudoEngine.move(st, mv[rng.nextInt(mv.length)].token,
                      auto: rng.nextInt(10) == 0)
                  .state;
        }
        if (st.phase != LudoPhase.gameOver) {
          expect(st.isActive(st.currentSeat), isTrue);
        }
        for (var i = 0; i < n; i++) {
          if (!st.isActive(i)) expect(st.tokens[i].every((p) => p == -1), isTrue);
        }
      }
      expect(st.phase, LudoPhase.gameOver);
      final all = st.config.teams.toSet();
      expect(st.ranking.toSet().length, all.length);
    }
  });
}
