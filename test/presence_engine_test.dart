import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/features/ludo/engine/engine.dart';

GameState newGame(int players, {List<int>? teams, List<bool>? bots, bool rankAll = true}) {
  final seats = [
    for (var i = 0; i < players; i++)
      SeatConfig(
        name: 'P$i',
        uid: 'u$i',
        kind: (bots != null && bots[i]) ? PlayerKind.bot : PlayerKind.human,
      ),
  ];
  return LudoEngine.newGame(GameConfig(seats: seats, teams: teams, rankAll: rankAll));
}

/// Survives a trip through JSON, like a state published to Firestore.
GameState wire(GameState s) =>
    GameState.fromJson(Map<String, dynamic>.from(jsonDecode(jsonEncode(s.toJson())) as Map));

/// Rolls a value that cannot move anything (no token has left the yard) and
/// passes, which hands the turn to the next seat.
GameState pass(GameState s) => LudoEngine.passTurn(LudoEngine.roll(s, 2));

void main() {
  group('state & serialisation', () {
    test('a new game has every seat connected', () {
      final g = newGame(4);
      expect(g.presence.every((p) => p == SeatPresence.connected), isTrue);
      expect(g.exits, <int>[]);
    });

    test('reconnect state survives the wire and keeps the game exactly as it was', () {
      var g = newGame(3);
      g = LudoEngine.roll(g, 6); // seat 0 has rolled a 6 and has not moved yet
      g.tokens[1][2] = 17;
      final dropped = LudoEngine.setReconnecting(g, 0, 60000);
      final back = wire(dropped);
      expect(back.presence[0], SeatPresence.reconnecting);
      expect(back.reconnectMs[0], 60000);
      expect(back.reconnectSeq[0], 1);
      // Turn order, dice, phase and tokens are untouched.
      expect(back.currentSeat, 0);
      expect(back.phase, LudoPhase.awaitMove);
      expect(back.dice, 6);
      expect(back.tokens[1][2], 17);
      expect(back.turnCount, g.turnCount);
    });

    test('states saved before presence existed still load', () {
      final json = Map<String, dynamic>.from(jsonDecode(jsonEncode(newGame(3).toJson())) as Map)
        ..remove('presence')
        ..remove('rcMs')
        ..remove('rcSeq')
        ..remove('exits');
      final g = GameState.fromJson(json);
      expect(g.presence.length, 3);
      expect(g.presence.every((p) => p == SeatPresence.connected), isTrue);
    });
  });

  group('reconnecting', () {
    test('coming back restores the seat and nothing else changes', () {
      var g = LudoEngine.roll(newGame(3), 6);
      final dropped = LudoEngine.setReconnecting(g, 0, 60000);
      final back = LudoEngine.setReconnected(dropped, 0);
      expect(back.presence[0], SeatPresence.connected);
      expect(back.reconnectMs[0], 0);
      expect(back.currentSeat, 0);
      expect(back.phase, LudoPhase.awaitMove);
      expect(back.dice, 6);
    });

    test('every drop gets a fresh sequence number', () {
      var g = newGame(3);
      g = LudoEngine.setReconnecting(g, 1, 60000);
      g = LudoEngine.setReconnected(g, 1);
      g = LudoEngine.setReconnecting(g, 1, 60000);
      expect(g.reconnectSeq[1], 2);
    });

    test('setReconnecting twice does not restart the window', () {
      var g = LudoEngine.setReconnecting(newGame(3), 1, 60000);
      final again = LudoEngine.setReconnecting(g, 1, 99999);
      expect(again.reconnectMs[1], 60000);
      expect(again.reconnectSeq[1], 1);
    });

    test('the turn is NOT skipped while a seat is reconnecting', () {
      var g = LudoEngine.setReconnecting(newGame(3), 1, 60000);
      g = pass(g); // 0 -> 1
      expect(g.currentSeat, 1);
      expect(g.presence[1], SeatPresence.reconnecting);
    });

    test('simultaneous drops and returns are independent', () {
      var g = newGame(4);
      g = LudoEngine.setReconnecting(g, 1, 60000);
      g = LudoEngine.setReconnecting(g, 2, 60000);
      expect(LudoEngine.reconnectingSeats(g), [1, 2]);
      g = LudoEngine.setReconnected(g, 1);
      expect(LudoEngine.reconnectingSeats(g), [2]);
      g = LudoEngine.removeSeat(g, 2, SeatPresence.disconnected);
      expect(LudoEngine.reconnectingSeats(g), <int>[]);
      expect(g.presence[1], SeatPresence.connected);
      expect(g.presence[2], SeatPresence.disconnected);
    });
  });

  group('removing a seat', () {
    test('its turns are skipped from then on', () {
      var g = newGame(4);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.disconnected);
      expect(g.currentSeat, 0);
      g = pass(g);
      expect(g.currentSeat, 2); // 1 skipped
      g = pass(g);
      expect(g.currentSeat, 3);
      g = pass(g);
      expect(g.currentSeat, 0);
      expect(LudoEngine.seatsInPlay(g), [0, 2, 3]);
    });

    test('removing the seat whose turn it is hands the turn on and drops the half-played roll', () {
      var g = LudoEngine.roll(newGame(3), 6); // seat 0 rolled, has not moved
      g = LudoEngine.removeSeat(g, 0, SeatPresence.left);
      expect(g.currentSeat, 1);
      expect(g.phase, LudoPhase.awaitRoll);
      expect(g.phase == LudoPhase.gameOver, isFalse);
    });

    test("the seat's tokens leave the board", () {
      var g = newGame(3);
      g.tokens[1] = [5, 12, -1, 30];
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(g.tokens[1], [-1, -1, -1, -1]);
      expect(g.tokens[0], [-1, -1, -1, -1]);
    });

    test('a seat that already finished keeps its tokens', () {
      var g = newGame(3);
      final fin = g.config.layout.finishProgress;
      g.tokens[1] = [fin, fin, fin, fin];
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(g.tokens[1], [fin, fin, fin, fin]);
    });

    test('removing twice changes nothing', () {
      var g = LudoEngine.removeSeat(newGame(4), 2, SeatPresence.left);
      final again = LudoEngine.removeSeat(g, 2, SeatPresence.disconnected);
      expect(again.presence[2], SeatPresence.left);
      expect(again.exits, [2]);
    });

    test('a reconnect window that expires removes the seat', () {
      var g = LudoEngine.setReconnecting(newGame(4), 2, 60000);
      g = LudoEngine.removeSeat(g, 2, SeatPresence.disconnected);
      expect(g.presence[2], SeatPresence.disconnected);
      expect(g.reconnectMs[2], 0);
    });

    test('removed seats cannot be revived by setReconnected', () {
      var g = LudoEngine.removeSeat(newGame(4), 2, SeatPresence.left);
      g = LudoEngine.setReconnected(g, 2);
      expect(g.presence[2], SeatPresence.left);
    });
  });

  group('match completion', () {
    test('two players: when one leaves the other wins', () {
      final g = LudoEngine.removeSeat(newGame(2), 0, SeatPresence.left);
      expect(g.phase, LudoPhase.gameOver);
      expect(g.ranking, [1, 0]);
    });

    test('three players: play continues after one leaves, ends when a second does', () {
      var g = newGame(3);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(g.phase == LudoPhase.gameOver, isFalse);
      g = LudoEngine.removeSeat(g, 0, SeatPresence.disconnected);
      expect(g.phase, LudoPhase.gameOver);
      expect(g.ranking.first, 2); // the last one standing wins
      expect(g.ranking, [2, 0, 1]); // later leaver ranks above earlier leaver
    });

    test('the survivor wins even without having finished a single token', () {
      var g = newGame(4);
      g = LudoEngine.removeSeat(g, 0, SeatPresence.left);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      g = LudoEngine.removeSeat(g, 2, SeatPresence.disconnected);
      expect(g.phase, LudoPhase.gameOver);
      expect(g.ranking.first, 3);
      expect(LudoEngine.standings(g).first.seats, [3]);
    });

    test('an earlier finisher stays ahead of the survivor', () {
      var g = newGame(3);
      final fin = g.config.layout.finishProgress;
      g.tokens[0] = [fin, fin, fin, fin];
      g.ranking.add(0);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(g.phase, LudoPhase.gameOver);
      expect(g.ranking, [0, 2, 1]);
    });

    test('"first to finish wins" games also end when one player is left', () {
      var g = newGame(3, rankAll: false);
      g = LudoEngine.removeSeat(g, 0, SeatPresence.left);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(g.phase, LudoPhase.gameOver);
      expect(g.ranking.first, 2);
    });

    test('nothing changes once the game is over, except recording who left', () {
      var g = LudoEngine.removeSeat(newGame(2), 0, SeatPresence.left);
      final rank = List<int>.of(g.ranking);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(g.ranking, rank);
      expect(g.phase, LudoPhase.gameOver);
      expect(LudoEngine.setReconnecting(g, 0, 1000).presence[0], SeatPresence.left);
    });

    test('bots count as players, humans are counted separately', () {
      var g = newGame(3, bots: [false, false, true]);
      expect(LudoEngine.humansInPlay(g), [0, 1]);
      g = LudoEngine.removeSeat(g, 0, SeatPresence.left);
      expect(g.phase == LudoPhase.gameOver, isFalse); // human vs bot carries on
      expect(LudoEngine.humansInPlay(g), [1]);
      expect(LudoEngine.seatsInPlay(g), [1, 2]);
      g = LudoEngine.removeSeat(g, 1, SeatPresence.left);
      expect(LudoEngine.humansInPlay(g), <int>[]);
      expect(g.phase, LudoPhase.gameOver);
    });
  });

  group('team games', () {
    // seats 0 & 2 are team 0, seats 1 & 3 are team 1
    GameState teams() => newGame(4, teams: [0, 1, 0, 1]);

    test('a team keeps playing while one of its seats remains', () {
      var g = teams();
      g = LudoEngine.removeSeat(g, 2, SeatPresence.left);
      expect(g.phase == LudoPhase.gameOver, isFalse);
      expect(LudoEngine.isTeamEliminated(g, 0), isFalse);
    });

    test('a team whose seats all left is eliminated, the other team wins', () {
      var g = teams();
      g = LudoEngine.removeSeat(g, 2, SeatPresence.left);
      g = LudoEngine.removeSeat(g, 0, SeatPresence.disconnected);
      expect(g.phase, LudoPhase.gameOver);
      expect(g.ranking, [1, 0]);
    });

    test('a departure can complete the team of the seat that is left', () {
      var g = teams();
      final fin = g.config.layout.finishProgress;
      g.tokens[0] = [fin, fin, fin, fin]; // seat 0 is home, may move seat 2's tokens
      g = LudoEngine.removeSeat(g, 2, SeatPresence.left);
      // Seat 2's team-mate (seat 0) is done and seat 2 is gone: team 0 is complete.
      expect(g.ranking.contains(0), isTrue);
    });
  });

  group('team turn hand-over', () {
    test("when a departure completes the current seat's team, the turn moves on", () {
      // Teams: {0,3}, {1,4}, {2,5}. Seat 0 is done and holds the turn (it may
      // move its partner's tokens); the partner, seat 3, leaves.
      var g = newGame(6, teams: [0, 1, 2, 0, 1, 2]);
      final fin = g.config.layout.finishProgress;
      g.tokens[0] = [fin, fin, fin, fin];
      expect(g.currentSeat, 0);
      g = LudoEngine.removeSeat(g, 3, SeatPresence.left);
      expect(g.ranking, [0]);
      expect(g.phase == LudoPhase.gameOver, isFalse);
      expect(g.currentSeat, 1);
      expect(g.phase, LudoPhase.awaitRoll);
    });
  });

  group('rotation never lands on a removed seat', () {
    test('for any combination of removals in a 6 player game', () {
      for (var mask = 0; mask < 63; mask++) {
        var g = newGame(6);
        for (var i = 0; i < 6; i++) {
          if (mask & (1 << i) != 0 && g.phase != LudoPhase.gameOver) {
            g = LudoEngine.removeSeat(g, i, i.isEven ? SeatPresence.left : SeatPresence.disconnected);
          }
        }
        if (g.phase == LudoPhase.gameOver) continue;
        for (var k = 0; k < 12; k++) {
          expect(LudoEngine.isSeatOut(g, g.currentSeat), isFalse);
          g = pass(g);
        }
      }
    });
  });
}
