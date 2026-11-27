import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../data/lan_backend.dart';
import '../data/online_repository.dart';
import '../data/sound_service.dart';
import '../engine/engine.dart';
import '../ui/seat_identity.dart' show isMySeat;
import 'quick_chat_controller.dart';

// ------------------------------------------------------------------ providers

final ludoStoreProvider = Provider<LudoStore>((ref) => LudoStore());

final ludoSoundProvider = Provider<LudoSound>((ref) {
  final s = LudoSound();
  s.warmUp(); // load the effects now, not on the first dice roll
  ref.onDispose(s.dispose);
  return s;
});

final onlineRepoProvider = Provider<LudoOnlineRepository>((ref) => LudoOnlineRepository());

/// Hotspot / local Wi-Fi rooms (no internet or Firebase needed).
final lanBackendProvider = Provider<LanBackend>((ref) => LanBackend());

/// The player's display name, chosen on first launch and editable from the
/// main menu. `null` (after loading) means the player has not chosen yet.
class PlayerNameController extends AsyncNotifier<String?> {
  static const maxLength = 12;

  @override
  Future<String?> build() => ref.read(ludoStoreProvider).loadPlayerName();

  Future<void> setName(String name) async {
    final t = name.trim();
    if (t.isEmpty) return;
    final clean = t.length > maxLength ? t.substring(0, maxLength) : t;
    await ref.read(ludoStoreProvider).savePlayerName(clean);
    state = AsyncData(clean);
  }
}

final playerNameProvider =
    AsyncNotifierProvider<PlayerNameController, String?>(PlayerNameController.new);

/// The interrupted local game (if any), for the "Resume" button.
final savedGameProvider = FutureProvider.autoDispose<SavedGame?>(
  (ref) => ref.read(ludoStoreProvider).loadGame(),
);

final ludoControllerProvider =
    NotifierProvider<LudoController, LudoUiState>(LudoController.new);

// ---------------------------------------------------------------------- state

class LudoUiState {
  /// Logical game state. It is replaced only after move animations finish.
  final GameState? game;
  final GameMode mode;

  /// Progress of every token as currently drawn (lags behind [game] while a
  /// move is being animated step by step).
  final List<List<int>> shown;

  /// True while an animation / bot / network round-trip is in progress. All
  /// user input is ignored while busy.
  final bool busy;
  final bool rolling;
  final int diceFace;
  final bool paused;
  final bool soundOn;
  final String? message;

  /// Online only.
  final int? mySeat;
  final bool isHost;
  final String? roomCode;
  final bool hostLeft;

  /// Online Quick Start game: shown without room code / host-guest wording.
  final bool quick;

  /// Online: wall-clock time (ms since epoch) when the current player's time
  /// runs out; null when no countdown applies (bot turn, game over, offline).
  final int? turnEndsAt;

  /// Important event for every player (e.g. somebody left). The screen shows
  /// it whenever [noticeSeq] changes.
  final String? notice;
  final int noticeSeq;

  /// Time a token takes per cell while it walks. The board glides the token
  /// for slightly longer than this so consecutive steps blend into one motion.
  static const int stepMs = 300;

  /// Marks a token in [shown] that must not be drawn at all (its owner left).
  static const int hiddenToken = -2;

  const LudoUiState({
    this.game,
    this.mode = GameMode.local,
    this.shown = const [],
    this.busy = false,
    this.rolling = false,
    this.diceFace = 1,
    this.paused = false,
    this.soundOn = true,
    this.message,
    this.mySeat,
    this.isHost = false,
    this.roomCode,
    this.hostLeft = false,
    this.quick = false,
    this.turnEndsAt,
    this.notice,
    this.noticeSeq = 0,
  });

  LudoUiState copyWith({
    GameState? game,
    GameMode? mode,
    List<List<int>>? shown,
    bool? busy,
    bool? rolling,
    int? diceFace,
    bool? paused,
    bool? soundOn,
    String? message,
    bool clearMessage = false,
    bool? hostLeft,
    int? turnEndsAt,
    bool clearTurn = false,
    String? notice,
    int? noticeSeq,
  }) =>
      LudoUiState(
        game: game ?? this.game,
        mode: mode ?? this.mode,
        shown: shown ?? this.shown,
        busy: busy ?? this.busy,
        rolling: rolling ?? this.rolling,
        diceFace: diceFace ?? this.diceFace,
        paused: paused ?? this.paused,
        soundOn: soundOn ?? this.soundOn,
        message: clearMessage ? null : (message ?? this.message),
        mySeat: mySeat,
        isHost: isHost,
        roomCode: roomCode,
        hostLeft: hostLeft ?? this.hostLeft,
        quick: quick,
        turnEndsAt: clearTurn ? null : (turnEndsAt ?? this.turnEndsAt),
        notice: notice ?? this.notice,
        noticeSeq: noticeSeq ?? this.noticeSeq,
      );
}

// ----------------------------------------------------------------- controller

/// Orchestrates a game: feeds dice values to [LudoEngine], animates results,
/// runs bots, autosaves local games and (online) acts as host or guest.
/// All rule decisions live in the engine; this class only sequences them.
class LudoController extends Notifier<LudoUiState> {
  final math.Random _rng = math.Random.secure();
  int _gen = 0; // bumped to cancel stale async work
  bool _disposed = false;

  StreamSubscription<RoomData>? _roomSub;
  /// Seconds each player gets for every single action (roll, or pick a token).
  /// Default per-move limit; each game carries its own in [GameConfig.turnSeconds].
  static const int turnSeconds = 30;
  Timer? _turnWatch;
  GameState? _timedState; // state the running countdown was last (re)started for
  // A new move whose countdown waits for its animation to finish (see _commit).
  GameState? _pendingClockState;
  int _pendingClockVersion = 0;
  String? _myUid;
  Future<void> _pubChain = Future<void>.value();
  final List<GameState> _remote = [];
  bool _applyingRemote = false;
  int _version = 0;

  LudoStore get _store => ref.read(ludoStoreProvider);
  LudoSound get _sound => ref.read(ludoSoundProvider);
  /// Room service of the running online game (Firestore, or the Wi-Fi host).
  RoomBackend? _backend;
  RoomBackend get _repo => _backend ?? ref.read(onlineRepoProvider);

  @override
  LudoUiState build() {
    ref.onDispose(() {
      _disposed = true;
      _gen++;
      _roomSub?.cancel();
      _turnWatch?.cancel();
    });
    _loadSoundPref();
    return const LudoUiState();
  }

  Future<void> _loadSoundPref() async {
    final on = await _store.loadSoundEnabled();
    if (_disposed) return;
    _sound.enabled = on;
    state = state.copyWith(soundOn: on);
  }

  bool _alive(int gen) => !_disposed && gen == _gen;

  /// Drives bot seats: local / AI games, and online private rooms where the
  /// host filled seats with bots. Online, the first human still in the game
  /// runs the bots, so it moves on if that player leaves.
  bool _isDriver(GameState? g) {
    if (g == null || _myUid == null) return false;
    for (var i = 0; i < g.config.seats.length; i++) {
      final s = g.config.seats[i];
      if (!s.isBot && g.isActive(i)) return s.uid == _myUid;
    }
    return false;
  }

  bool get _isAuthority =>
      state.mode != GameMode.online || _isDriver(state.game);

  /// Online: after another device's update, take over bot turns if we are
  /// the bot driver.
  void _afterRemote() {
    final g = state.game;
    if (g == null || state.mode != GameMode.online || g.phase == LudoPhase.gameOver) return;
    if (!_isDriver(g) || !g.config.seats[g.currentSeat].isBot) return;
    if (g.phase == LudoPhase.awaitRoll) {
      _scheduleBot();
    } else if (g.phase == LudoPhase.awaitMove && !state.busy) {
      state = state.copyWith(busy: true);
      unawaited(_afterRoll(g, _gen));
    }
  }

  List<List<int>> _copyTokens(GameState g) =>
      g.tokens.map((t) => List<int>.of(t)).toList();

  Future<void> _pauseGate(int gen) async {
    while (_alive(gen) && state.paused) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _delay(int ms, int gen) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    await _pauseGate(gen);
  }

  // ----------------------------------------------------------------- lifecycle

  /// Starts a local game (hot-seat and/or bots) on this device.
  void startLocal(GameConfig config, GameMode mode) {
    _detachOnline();
    _gen++;
    final g = LudoEngine.newGame(config);
    state = LudoUiState(
      game: g,
      mode: mode == GameMode.online ? GameMode.local : mode,
      shown: _copyTokens(g),
      soundOn: state.soundOn,
    );
    _store.saveGame(g, state.mode);
    _afterCommit();
  }

  /// Restores the autosaved local game. Returns false if there is none.
  Future<bool> resume() async {
    final saved = await _store.loadGame();
    if (saved == null || _disposed) return false;
    _detachOnline();
    _gen++;
    state = LudoUiState(
      game: saved.state,
      mode: saved.mode,
      shown: _copyTokens(saved.state),
      soundOn: state.soundOn,
    );
    _afterCommit();
    return true;
  }

  /// Joins an online game that the host has started (or hosts it).
  void attachOnline({
    required String code,
    required String uid,
    required bool host,
    required GameState initial,
    required int version,
    bool quick = false,
    RoomBackend? backend,
  }) {
    _detachOnline();
    _backend = backend;
    _gen++;
    int? mySeat;
    for (var i = 0; i < initial.config.seats.length; i++) {
      if (initial.config.seats[i].uid == uid) mySeat = i;
    }
    _version = version;
    _myUid = uid;
    _pubChain = Future<void>.value();
    state = LudoUiState(
      game: initial,
      mode: GameMode.online,
      shown: _copyTokens(initial),
      soundOn: state.soundOn,
      mySeat: mySeat,
      isHost: host,
      roomCode: code,
      quick: quick,
    );
    _roomSub = _repo.watchRoom(code).listen(_onRoom, onError: (_) {});
    ref.read(quickChatProvider.notifier).attach(
          backend: _repo,
          code: code,
          seatOf: _seatOfUid,
        );
    // Every device is equal: whoever has to act (a human on their own turn, or
    // the bot driver for bot seats) does so from its own screen.
    _markTurnStart(initial, version);
    _afterRemote();
  }

  void _detachOnline() {
    _turnWatch?.cancel();
    _roomSub?.cancel();
    _roomSub = null;
    _remote.clear();
    _applyingRemote = false;
    ref.read(quickChatProvider.notifier).detach();
  }

  /// Seat of the player with [uid] in the running online game, or null when
  /// they are not in it (or have left). Quick chat bubbles use this to find
  /// the yard a message belongs to.
  int? _seatOfUid(String uid) {
    final g = state.game;
    if (g == null) return null;
    for (var i = 0; i < g.config.seats.length; i++) {
      if (g.config.seats[i].uid == uid && g.isActive(i)) return i;
    }
    return null;
  }

  void restart() {
    final g = state.game;
    if (g == null) return;
    if (state.mode == GameMode.online) {
      if (!state.isHost) return;
      _gen++;
      final fresh = LudoEngine.newGame(g.config);
      state = LudoUiState(
        game: fresh,
        mode: GameMode.online,
        shown: _copyTokens(fresh),
        soundOn: state.soundOn,
        mySeat: state.mySeat,
        isHost: true,
        roomCode: state.roomCode,
        quick: state.quick,
      );
      _publish(fresh);
      _afterCommit();
      return;
    }
    startLocal(g.config, state.mode);
  }

  /// Leaves the current game. Unfinished local games stay saved for Resume.
  Future<void> exitGame() async {
    final code = state.roomCode;
    final mySeat = state.mySeat;
    final online = state.mode == GameMode.online;
    final over = state.game?.phase == LudoPhase.gameOver;
    _gen++;
    _detachOnline();
    state = LudoUiState(soundOn: state.soundOn);
    if (online && code != null) {
      try {
        // Our seat is taken over by a bot; the others keep playing.
        await _repo.leaveGame(code, mySeat);
      } catch (_) {}
    } else if (over) {
      await _store.clearGame();
    }
  }

  void setPaused(bool paused) {
    if (state.mode == GameMode.online) return; // never freeze a shared game
    state = state.copyWith(paused: paused);
    final g = state.game;
    if (paused && g != null) _store.saveGame(g, state.mode);
  }

  void toggleSound() {
    final on = !state.soundOn;
    _sound.enabled = on;
    state = state.copyWith(soundOn: on);
    _store.saveSoundEnabled(on);
  }

  // --------------------------------------------------------------- user input

  bool _isMyTurn(GameState g) {
    final seat = g.config.seats[g.currentSeat];
    if (seat.isBot) return false;
    if (state.mode == GameMode.online) return state.mySeat == g.currentSeat;
    return true;
  }

  bool get canRoll {
    final g = state.game;
    if (g == null || state.busy || state.paused) return false;
    return g.phase == LudoPhase.awaitRoll && _isMyTurn(g);
  }

  bool get canPickToken {
    final g = state.game;
    if (g == null || state.busy || state.paused) return false;
    return g.phase == LudoPhase.awaitMove && _isMyTurn(g);
  }

  Future<void> rollTapped() async {
    if (!canRoll) return;
    await _performRoll();
  }

  Future<void> tokenTapped(TokenRef ref) async {
    if (!canPickToken) return;
    final g = state.game!;
    if (!LudoEngine.legalMoves(g).any((m) => m.token == ref)) return;
    await _performMove(ref);
  }

  // ------------------------------------------------------------- game actions

  GameState? _tryRoll(GameState g, int value) {
    try {
      return LudoEngine.roll(g, value);
    } on IllegalActionException {
      return null;
    }
  }

  MoveOutcome? _tryMove(GameState g, TokenRef ref, {bool auto = false}) {
    try {
      return LudoEngine.move(g, ref, auto: auto);
    } on IllegalActionException {
      return null;
    }
  }

  Future<void> _animateDice(int value, int gen) async {
    state = state.copyWith(rolling: true);
    _sound.play(Sfx.dice);
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 75));
      if (!_alive(gen)) return;
      state = state.copyWith(diceFace: _rng.nextInt(6) + 1);
    }
    state = state.copyWith(diceFace: value);
  }

  Future<void> _performRoll() async {
    final gen = _gen;
    final g = state.game;
    if (g == null || g.phase != LudoPhase.awaitRoll) return;
    state = state.copyWith(busy: true, clearMessage: true);
    final value = _rng.nextInt(6) + 1;
    final rolled = _tryRoll(g, value);
    if (rolled == null) {
      state = state.copyWith(busy: false, rolling: false);
      return;
    }
    // Publish first so guests animate the roll at the same time as the host.
    unawaited(_publish(rolled));
    await _animateDice(value, gen);
    if (!_alive(gen)) return;
    state = state.copyWith(game: rolled, rolling: false, diceFace: value);
    await _afterRoll(rolled, gen);
  }

  /// "You" when [seat] is the player at this device, otherwise the seat name.
  String _who(GameState g, int seat) =>
      isMySeat(state, seat) ? 'You' : g.config.seats[seat].name;

  /// Picks the verb form that matches [_who]: "You roll again" / "Ann rolls again".
  String _verb(GameState g, int seat, String you, String other) =>
      isMySeat(state, seat) ? you : other;

  /// Decides what happens after a roll is on the table: skip the turn when
  /// nothing can move, let a bot choose, or wait for a human to pick.
  Future<void> _afterRoll(GameState rolled, int gen) async {
    final moves = LudoEngine.legalMoves(rolled);
    final seat = rolled.config.seats[rolled.currentSeat];
    final who = _who(rolled, rolled.currentSeat);
    final v = rolled.dice;

    if (moves.isEmpty) {
      state = state.copyWith(
          busy: true,
          message: LudoEngine.isSixesForfeit(rolled)
              ? '$who rolled three 6s in a row - turn lost'
              : '$who rolled $v - no valid move');
      await _delay(1100, gen);
      if (!_alive(gen)) return;
      final passed = LudoEngine.passTurn(rolled);
      await _commit(passed, gen);
      if (!_alive(gen)) return;
      state = state.copyWith(busy: false, clearMessage: true);
      _afterCommit();
      return;
    }

    if (seat.isBot) {
      await _delay(650, gen);
      if (!_alive(gen)) return;
      final pick = LudoBot.choose(rolled, moves, seat.level, _rng);
      await _performMove(pick.token);
      return;
    }

    if (moves.length == 1) {
      // Only one legal move (every mode): play it for the player after a short beat.
      state = state.copyWith(busy: true, message: '$who rolled $v - only one move');
      await _delay(600, gen);
      if (!_alive(gen)) return;
      await _performMove(moves.first.token);
      return;
    }

    state = state.copyWith(
      busy: false,
      message: v == 6
          ? '$who rolled a 6 - choose a token'
          : '$who rolled $v - choose a token',
    );
  }

  /// [auto] is true when the move is played for a player whose time ran out.
  Future<void> _performMove(TokenRef ref, {bool auto = false}) async {
    final gen = _gen;
    final g = state.game;
    if (g == null || g.phase != LudoPhase.awaitMove) return;
    final out = _tryMove(g, ref, auto: auto);
    if (out == null) {
      state = state.copyWith(busy: false);
      return;
    }
    state = state.copyWith(busy: true, clearMessage: true);
    await _commit(out.state, gen);
    if (!_alive(gen)) return;

    String? msg;
    final e = out.event;
    if (e.gameOver) {
      msg = 'Game over!';
    } else if (e.teamCompleted) {
      msg = '${_teamLabel(g, g.teamOf(e.actor))} brought every token home!';
    } else if (e.captured.isNotEmpty) {
      final names = e.captured.map((t) => g.config.seats[t.seat].name).toSet().join(', ');
      msg = '${_who(g, e.actor)} captured $names!';
    } else if (e.reachedFinish) {
      msg = 'A token reached home!';
    } else if (e.extraTurn) {
      msg = '${_who(g, e.actor)} ${_verb(g, e.actor, 'roll', 'rolls')} again';
    }
    state = state.copyWith(busy: false, message: msg, clearMessage: msg == null);
    _afterCommit();
  }

  String _teamLabel(GameState g, int team) {
    final names = <String>[
      for (var i = 0; i < g.config.playerCount; i++)
        if (g.config.teams[i] == team) g.config.seats[i].name,
    ];
    return names.join(' & ');
  }

  /// Animates the transition to [next], then makes it the logical state,
  /// autosaves (local) and publishes (online host).
  Future<void> _commit(GameState next, int gen, {bool publish = true}) async {
    // Publish before animating so guests animate in step with the host.
    if (publish) unawaited(_publish(next, deferClock: true));
    _announcePresence(state.game, next);
    await _animateTokens(next, gen);
    if (!_alive(gen)) return;
    state = state.copyWith(game: next, shown: _copyTokens(next));
    // The movement animation is done: only now does the next countdown start.
    _releaseTurnClock(next);
    if (state.mode != GameMode.online) {
      if (next.phase == LudoPhase.gameOver) {
        await _store.clearGame();
      } else {
        await _store.saveGame(next, state.mode);
      }
    }
    if (next.phase == LudoPhase.gameOver) _sound.play(Sfx.win);
  }

  /// Tells every remaining player when somebody left the game or was removed
  /// for missing too many turns. Runs on every device from the state change
  /// itself, so nobody depends on the leaving player's connection.
  void _announcePresence(GameState? before, GameState after) {
    if (before == null || state.mode != GameMode.online) return;
    final lines = <String>[];
    for (var i = 0; i < after.config.playerCount; i++) {
      if (!before.isActive(i) || after.isActive(i)) continue;
      if (state.mySeat == i) continue; // the screen tells the player themselves
      final name = after.config.seats[i].name;
      lines.add(after.presence[i] == SeatPresence.left
          ? '$name left the game'
          : '$name was removed for missing ${LudoEngine.maxMissedTurns} turns in a row');
    }
    if (lines.isEmpty) return;
    state = state.copyWith(notice: lines.join('\n'), noticeSeq: state.noticeSeq + 1);
  }

  /// The single token that bounced back off home in this commit, or null.
  ///
  /// Only the token that was actually moved can bounce, so this never looks at
  /// tokens that merely sit in a home lane. The dice persists in [next] until
  /// the following roll, so it is the dice used for the move.
  TokenRef? _bounceMover(GameState next, List<List<int>> cur) {
    final prev = state.game;
    if (!next.config.bounceBack || prev == null) return null;
    // Only a move commit can bounce (a roll commit leaves tokens untouched).
    if (prev.phase != LudoPhase.awaitMove || LudoEngine.isSixesForfeit(prev)) {
      return null;
    }
    final finish = next.config.layout.finishProgress;
    final d = next.dice;

    // A moved token changes cell; a captured one goes to -1. If exactly one
    // active token changed to a board cell, that is the mover.
    for (var s = 0; s < cur.length; s++) {
      if (!next.isActive(s)) continue;
      for (var i = 0; i < next.config.tokenCount; i++) {
        final a = cur[s][i];
        final b = next.tokens[s][i];
        if (a == b || b < 0) continue;
        final bounced = a >= 0 && a + d > finish && b == 2 * finish - (a + d);
        return bounced ? TokenRef(s, i) : null;
      }
    }

    // Nothing changed cell: a bounce that lands on its own start cell
    // (d == 2 * (finish - a)). Pick among the tokens allowed to move.
    for (final ref in LudoEngine.actingTokens(prev, prev.currentSeat)) {
      final a = cur[ref.seat][ref.index];
      if (a >= 0 && a + d > finish && a == 2 * finish - (a + d)) return ref;
    }
    return null;
  }

  Future<void> _animateTokens(GameState next, int gen) async {
    final cur = state.shown.map((t) => List<int>.of(t)).toList();
    if (cur.length != next.tokens.length) {
      state = state.copyWith(shown: _copyTokens(next));
      return;
    }
    final layout = next.config.layout;
    final movers = <TokenRef>[];
    final captured = <TokenRef>[];
    final bouncer = _bounceMover(next, cur);
    var removedAny = false;
    for (var s = 0; s < cur.length; s++) {
      if (!next.isActive(s)) {
        // The player left: their tokens disappear from the board at once.
        for (var i = 0; i < next.config.tokenCount; i++) {
          if (cur[s][i] != LudoUiState.hiddenToken) {
            cur[s][i] = LudoUiState.hiddenToken;
            removedAny = true;
          }
        }
        continue;
      }
      for (var i = 0; i < next.config.tokenCount; i++) {
        final a = cur[s][i];
        final b = next.tokens[s][i];
        // A bounce can end exactly on its start cell, so it is not "changed".
        if (bouncer != null && bouncer.seat == s && bouncer.index == i) {
          movers.add(TokenRef(s, i));
          continue;
        }
        if (a == b) continue;
        if (b == -1) {
          captured.add(TokenRef(s, i));
        } else {
          movers.add(TokenRef(s, i));
        }
      }
    }

    void show() =>
        state = state.copyWith(shown: cur.map((t) => List<int>.of(t)).toList());

    if (removedAny) show();

    for (final m in movers) {
      final a = cur[m.seat][m.index];
      final b = next.tokens[m.seat][m.index];
      if (a < 0) {
        cur[m.seat][m.index] = b;
        show();
        // Play the sound when the token has landed, not when it starts to move.
        await _delay(LudoUiState.stepMs + 40, gen);
        if (!_alive(gen)) return;
        _sound.play(Sfx.enter);
      } else if (bouncer != null && bouncer.seat == m.seat && bouncer.index == m.index) {
        // Bounce back: walk to home, then back by the leftover pips.
        for (var p = a + 1; p <= layout.finishProgress; p++) {
          cur[m.seat][m.index] = p;
          show();
          await _delay(LudoUiState.stepMs, gen);
          if (!_alive(gen)) return;
          _sound.play(Sfx.move);
        }
        for (var p = layout.finishProgress - 1; p >= b; p--) {
          cur[m.seat][m.index] = p;
          show();
          await _delay(LudoUiState.stepMs, gen);
          if (!_alive(gen)) return;
          _sound.play(Sfx.move);
        }
      } else {
        for (var p = a + 1; p <= b; p++) {
          cur[m.seat][m.index] = p;
          show();
          // The token glides for stepMs + 40 ms; tick as it lands on the cell.
          await _delay(LudoUiState.stepMs, gen);
          if (!_alive(gen)) return;
          _sound.play(Sfx.move);
        }
      }
      if (b >= layout.finishProgress) _sound.play(Sfx.finish);
    }
    if (captured.isNotEmpty) {
      _sound.play(Sfx.capture);
      for (final c in captured) {
        cur[c.seat][c.index] = -1;
      }
      show();
      await _delay(480, gen);
    }
  }

  /// Hands control to bots / resumes half-finished turns.
  void _afterCommit() {
    final g = state.game;
    if (g == null || g.phase == LudoPhase.gameOver || !_isAuthority) return;
    final seat = g.config.seats[g.currentSeat];
    if (g.phase == LudoPhase.awaitMove) {
      // Only reachable after resuming a saved game or restoring mid-turn.
      state = state.copyWith(busy: true);
      final gen = _gen;
      unawaited(_afterRoll(g, gen));
      return;
    }
    if (seat.isBot) _scheduleBot();
  }

  void _scheduleBot() {
    final gen = _gen;
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      if (!_alive(gen)) return;
      await _pauseGate(gen);
      if (!_alive(gen)) return;
      final g = state.game;
      if (g == null || g.phase != LudoPhase.awaitRoll) return;
      if (!g.config.seats[g.currentSeat].isBot || !_isAuthority) return;
      if (state.busy) {
        _scheduleBot(); // something else is animating; try again shortly
        return;
      }
      await _performRoll();
    });
  }

  // ------------------------------------------------------------------- online

  /// Online: sends [g] to the shared room record. Writes are queued in order
  /// and only succeed on top of the version we last saw; on a conflict the
  /// device adopts the stored state. Animations never wait for this.
  Future<void> _publish(GameState g, {bool deferClock = false}) {
    if (state.mode != GameMode.online) return Future<void>.value();
    final code = state.roomCode;
    if (code == null) return Future<void>.value();
    final base = _version;
    _version += 1;
    final next = _version;
    _markTurnStart(g, next, deferClock: deferClock);
    return _pubChain = _pubChain.then((_) async {
      // Let the roll / move animation draw its first frames before the
      // network call starts, so the write never delays the animation start.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        final ok = await _repo.publishStateCas(code, g, base, next);
        if (!ok) await _resync(code);
      } catch (e) {
        if (!_disposed) state = state.copyWith(message: 'Sync problem: $e');
      }
    });
  }

  // ------------------------------------------------------------- turn timer

  /// A new move begins (new roll, new token pick, extra turn, next player):
  /// restart the countdown. Every device calls this when it learns of the new
  /// state, so the countdowns agree to within the network delay.
  ///
  /// With [deferClock] the caller is about to animate the move; the countdown
  /// then starts only when [_releaseTurnClock] is called after that animation,
  /// so the player's time is not eaten by the movement.
  void _markTurnStart(GameState g, int version, {bool deferClock = false}) {
    _turnWatch?.cancel();
    _pendingClockState = null;
    final prev = _timedState;
    _timedState = g;
    if (state.mode != GameMode.online || g.phase == LudoPhase.gameOver) {
      state = state.copyWith(clearTurn: true);
      return;
    }
    // Host chose "no limit": no countdown, no auto-move, nobody is timed out.
    if (g.config.turnSeconds <= 0) {
      state = state.copyWith(clearTurn: true);
      return;
    }
    final seat = g.config.seats[g.currentSeat];
    if (seat.isBot) {
      state = state.copyWith(clearTurn: true);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    // Rolling the dice does not restart the clock: the player has one budget
    // for roll + token pick. Only a made move (or a skipped turn) restarts it.
    final isRollResult = prev != null &&
        state.turnEndsAt != null &&
        prev.phase == LudoPhase.awaitRoll &&
        g.phase == LudoPhase.awaitMove &&
        prev.currentSeat == g.currentSeat &&
        prev.turnCount == g.turnCount;
    if (deferClock && !isRollResult) {
      // Wait for the animation: hide the countdown and arm nothing yet.
      _pendingClockState = g;
      _pendingClockVersion = version;
      state = state.copyWith(clearTurn: true);
      return;
    }
    final endsAt = isRollResult ? state.turnEndsAt! : now + g.config.turnSeconds * 1000;
    _armTurn(g, version, endsAt);
  }

  /// Starts the countdown that was held back for [g] once its animation is done.
  void _releaseTurnClock(GameState g) {
    final pending = _pendingClockState;
    if (pending == null || !identical(pending, g)) return;
    _pendingClockState = null;
    final seat = g.config.seats[g.currentSeat];
    if (state.mode != GameMode.online ||
        g.phase == LudoPhase.gameOver ||
        g.config.turnSeconds <= 0 ||
        seat.isBot) {
      return;
    }
    final endsAt = DateTime.now().millisecondsSinceEpoch + g.config.turnSeconds * 1000;
    _armTurn(g, _pendingClockVersion, endsAt);
  }

  /// Shows the countdown ending at [endsAt] and schedules the timeout action.
  void _armTurn(GameState g, int version, int endsAt) {
    _turnWatch?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    final seat = g.config.seats[g.currentSeat];
    state = state.copyWith(turnEndsAt: endsAt);
    final mine = seat.uid != null && seat.uid == _myUid;
    if (!mine && state.mySeat == null) return;
    // A player who was removed no longer acts, not even as a backup.
    final me = state.mySeat;
    if (me != null && !g.isActive(me)) return;
    // The player acts at 0s; every other seated device is a backup 4s later
    // (covers a player whose app died). Whoever writes first wins.
    final left = endsAt - now;
    final ms = (left < 0 ? 0 : left) + (mine ? 0 : 4000);
    final gen = _gen;
    _turnWatch = Timer(Duration(milliseconds: ms), () => _onTurnTimeout(version, gen));
  }

  Future<void> _onTurnTimeout(int version, int gen) async {
    if (!_alive(gen) || state.mode != GameMode.online || version != _version) return;
    final g = state.game;
    if (g == null || g.phase == LudoPhase.gameOver) return;
    if (state.busy) {
      // An animation is still running; try again shortly.
      _turnWatch = Timer(const Duration(milliseconds: 400), () => _onTurnTimeout(version, gen));
      return;
    }
    if (g.phase == LudoPhase.awaitMove) {
      final moves = LudoEngine.legalMoves(g);
      if (moves.isEmpty) {
        // The roller's own device passes the turn. If it vanished after the
        // roll, a backup device passes it so the game cannot stall.
        final owner = g.config.seats[g.currentSeat].uid;
        if (owner != null && owner == _myUid) return;
        state = state.copyWith(busy: true);
        await _commit(LudoEngine.passTurn(g), gen);
        if (!_alive(gen)) return;
        state = state.copyWith(busy: false);
        _afterCommit();
        return;
      }
      await _performMove(moves[_rng.nextInt(moves.length)].token, auto: true);
    } else {
      state = state.copyWith(busy: true, message: '${_who(g, g.currentSeat)} ran out of time');
      final passed = LudoEngine.skipRoll(g);
      await _commit(passed, gen);
      if (!_alive(gen)) return;
      state = state.copyWith(busy: false);
      _afterCommit();
    }
  }

  /// Replaces our view with the stored room state (after a write conflict).
  Future<void> _resync(String code) async {
    final room = await _repo.getRoom(code);
    final js = room?.stateJson;
    if (room == null || js == null || _disposed) return;
    final GameState g;
    try {
      g = GameState.fromJson(Map<String, dynamic>.from(jsonDecode(js) as Map));
    } catch (_) {
      return;
    }
    _announcePresence(state.game, g);
    _gen++;
    _remote.clear();
    _applyingRemote = false;
    _version = room.version;
    _markTurnStart(g, room.version);
    state = state.copyWith(
      game: g,
      shown: _copyTokens(g),
      busy: false,
      rolling: false,
      clearMessage: true,
    );
    _afterRemote();
  }

  void _onRoom(RoomData room) {
    if (state.mode != GameMode.online) return;
    if (room.status == 'closed' && !state.isHost && state.game?.phase != LudoPhase.gameOver) {
      // Wi-Fi rooms report a lost connection to the host this way.
      state = state.copyWith(message: 'The room was closed or the connection to the host was lost');
    }
    if (room.version <= _version) return;
    final js = room.stateJson;
    if (js == null) return;
    final GameState next;
    try {
      next = GameState.fromJson(Map<String, dynamic>.from(jsonDecode(js) as Map));
    } catch (_) {
      return;
    }
    _version = room.version;
    _markTurnStart(next, room.version, deferClock: true);
    _remote.add(next);
    _drainRemote();
  }

  /// Guest: replays host updates in order with the same animations.
  Future<void> _drainRemote() async {
    if (_applyingRemote) return;
    _applyingRemote = true;
    final gen = _gen;
    try {
      while (_remote.isNotEmpty && _alive(gen)) {
        final next = _remote.removeAt(0);
        final cur = state.game;
        state = state.copyWith(busy: true, clearMessage: true);
        if (cur != null && next.rollCount > cur.rollCount) {
          await _animateDice(next.dice, gen);
          if (!_alive(gen)) return;
          state = state.copyWith(rolling: false, diceFace: next.dice);
        }
        await _commit(next, gen, publish: false);
        if (!_alive(gen)) return;
        state = state.copyWith(busy: false);
      }
      _afterRemote();
    } finally {
      _applyingRemote = false;
    }
  }
}