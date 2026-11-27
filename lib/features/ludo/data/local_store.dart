import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/engine.dart';

class SavedGame {
  final GameState state;
  final GameMode mode;
  final DateTime savedAt;
  const SavedGame(this.state, this.mode, this.savedAt);
}

/// Persists an interrupted local game and a few settings.
class LudoStore {
  static const _kGame = 'ludo.savedGame.v1';
  static const _kSound = 'ludo.sound';
  static const _kName = 'ludo.playerName';
  static const _kBoardStyle = 'ludo.boardStyle';
  static const _kTokenStyle = 'ludo.tokenStyle';
  static const _kDiceStyle = 'ludo.diceStyle';
  static const _kBoardCustom = 'ludo.boardCustom';

  Future<void> saveGame(GameState state, GameMode mode) async {
    if (mode == GameMode.online || state.phase == LudoPhase.gameOver) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kGame,
        jsonEncode({
          'mode': mode.index,
          'savedAt': DateTime.now().toIso8601String(),
          'state': state.toJson(),
        }),
      );
    } catch (_) {
      // Saving is best effort; never break gameplay because of storage.
    }
  }

  Future<SavedGame?> loadGame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kGame);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final state = GameState.fromJson(Map<String, dynamic>.from(j['state'] as Map));
      if (state.phase == LudoPhase.gameOver) return null;
      return SavedGame(
        state,
        GameMode.values[(j['mode'] as num).toInt()],
        DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null; // corrupt or from an incompatible version
    }
  }

  Future<void> clearGame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGame);
    } catch (_) {}
  }

  /// The name the player picked on first launch (null until chosen).
  Future<String?> loadPlayerName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kName)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePlayerName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kName, name);
    } catch (_) {}
  }

  /// Saved look of the board / tokens as (boardIndex, tokenIndex).
  Future<(int, int)> loadStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt(_kBoardStyle) ?? 0, prefs.getInt(_kTokenStyle) ?? 0);
    } catch (_) {
      return (0, 0);
    }
  }

  Future<void> saveStyle(int board, int token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBoardStyle, board);
      await prefs.setInt(_kTokenStyle, token);
    } catch (_) {}
  }

  /// Saved dice look (index into DiceStyle).
  Future<int> loadDiceStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_kDiceStyle) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> saveDiceStyle(int dice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDiceStyle, dice);
    } catch (_) {}
  }

  /// The player's per-option board tweaks (see BoardCustom), as key -> int.
  Future<Map<String, int>> loadBoardCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBoardCustom);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is int) e.key.toString(): e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveBoardCustom(Map<String, int> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBoardCustom, jsonEncode(values));
    } catch (_) {}
  }

  Future<bool> loadSoundEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kSound) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveSoundEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSound, value);
    } catch (_) {}
  }
}
