import 'board_layout.dart';

enum PlayerKind { human, bot }

enum BotLevel { easy, medium, hard }

enum LudoPhase { awaitRoll, awaitMove, gameOver }

enum GameMode { local, ai, online }

/// Whether a seat is still taking part. A seat that is not [active] has no
/// tokens on the board and is skipped for the rest of the game.
///  * [left]     - the player left the game on purpose.
///  * [inactive] - the player missed too many turns in a row.
enum SeatPresence { active, left, inactive }

/// Identifies one token: [seat] is the owning seat, [index] is 0..3.
class TokenRef {
  final int seat;
  final int index;
  const TokenRef(this.seat, this.index);

  @override
  bool operator ==(Object other) =>
      other is TokenRef && other.seat == seat && other.index == index;

  @override
  int get hashCode => seat * 8 + index;

  @override
  String toString() => 'Token($seat:$index)';
}

class SeatConfig {
  final String name;
  final PlayerKind kind;
  final BotLevel level;

  /// Firebase uid of the human controlling this seat (online games only).
  final String? uid;

  const SeatConfig({
    required this.name,
    this.kind = PlayerKind.human,
    this.level = BotLevel.medium,
    this.uid,
  });

  bool get isBot => kind == PlayerKind.bot;

  SeatConfig copyWith({String? name, PlayerKind? kind, BotLevel? level, String? uid}) =>
      SeatConfig(
        name: name ?? this.name,
        kind: kind ?? this.kind,
        level: level ?? this.level,
        uid: uid ?? this.uid,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.index,
        'level': level.index,
        if (uid != null) 'uid': uid,
      };

  factory SeatConfig.fromJson(Map<String, dynamic> j) => SeatConfig(
        name: j['name'] as String,
        kind: PlayerKind.values[(j['kind'] as num).toInt()],
        level: BotLevel.values[(j['level'] as num).toInt()],
        uid: j['uid'] as String?,
      );
}

class GameConfig {
  final List<SeatConfig> seats;

  /// Team id of every seat. Without teams this is simply 0,1,2,...
  final List<int> teams;

  /// Extra roll after capturing an opponent (rolling a 6 always grants one).
  final bool bonusOnCapture;

  /// Extra roll after bringing a token home.
  final bool bonusOnFinish;

  /// Extra roll after rolling a 1 (rolling a 6 always grants one).
  final bool bonusOnOne;

  /// A 1 can bring a token out of the yard (a 6 always can).
  final bool enterOnOne;

  /// Keep playing until every ranking is decided (otherwise stop at the winner).
  final bool rankAll;

  /// Tokens each player has (1-4). Unused yard spots stay empty.
  final int tokenCount;

  /// One token per player starts the game already out of the yard, on its
  /// start square.
  final bool oneTokenOut;

  /// Landing on a square holding two or more opponent tokens captures all of
  /// them. When off, such a stack is safe and nobody is captured there.
  final bool stackedCapture;

  /// Rolling three 6s in a row ends the turn: the third 6 gives no move.
  final bool threeSixesForfeit;

  /// A token that overshoots home bounces back by the extra pips instead of
  /// needing the exact roll.
  final bool bounceBack;

  /// Time limit for one move in online games, in seconds. 0 = no limit.
  /// Offline modes never use it.
  final int turnSeconds;

  GameConfig({
    required List<SeatConfig> seats,
    List<int>? teams,
    this.bonusOnCapture = true,
    this.bonusOnFinish = true,
    this.bonusOnOne = false,
    this.enterOnOne = false,
    this.rankAll = true,
    this.tokenCount = 4,
    this.oneTokenOut = false,
    this.stackedCapture = true,
    this.threeSixesForfeit = true,
    this.bounceBack = false,
    this.turnSeconds = 30,
  })  : seats = List.unmodifiable(seats),
        teams = List.unmodifiable(
            teams ?? List<int>.generate(seats.length, (i) => i)) {
    if (seats.length < 2 || seats.length > 6) {
      throw ArgumentError('Ludo needs 2 to 6 players, got ${seats.length}');
    }
    if (this.teams.length != seats.length) {
      throw ArgumentError('teams must have one entry per seat');
    }
    if (tokenCount < 1 || tokenCount > 4) {
      throw ArgumentError('Ludo needs 1 to 4 tokens per player, got $tokenCount');
    }
  }

  late final BoardLayout layout = BoardLayout.forPlayers(seats.length);

  int get playerCount => seats.length;

  bool get teamMode => teams.toSet().length < seats.length;

  Map<String, dynamic> toJson() => {
        'seats': seats.map((s) => s.toJson()).toList(),
        'teams': teams,
        'bonusOnCapture': bonusOnCapture,
        'bonusOnFinish': bonusOnFinish,
        'bonusOnOne': bonusOnOne,
        'enterOnOne': enterOnOne,
        'rankAll': rankAll,
        'tokenCount': tokenCount,
        'oneTokenOut': oneTokenOut,
        'stackedCapture': stackedCapture,
        'threeSixesForfeit': threeSixesForfeit,
        'bounceBack': bounceBack,
        'turnSeconds': turnSeconds,
      };

  factory GameConfig.fromJson(Map<String, dynamic> j) => GameConfig(
        seats: (j['seats'] as List)
            .map((e) => SeatConfig.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        teams: (j['teams'] as List).map((e) => (e as num).toInt()).toList(),
        bonusOnCapture: j['bonusOnCapture'] as bool? ?? false,
        bonusOnFinish: j['bonusOnFinish'] as bool? ?? false,
        bonusOnOne: j['bonusOnOne'] as bool? ?? false,
        enterOnOne: j['enterOnOne'] as bool? ?? false,
        rankAll: j['rankAll'] as bool? ?? true,
        tokenCount: ((j['tokenCount'] as num?)?.toInt() ?? 4).clamp(1, 4),
        oneTokenOut: j['oneTokenOut'] as bool? ?? false,
        // Older saves / rooms were played with stacked capture and without
        // the other two rules.
        stackedCapture: j['stackedCapture'] as bool? ?? true,
        threeSixesForfeit: j['threeSixesForfeit'] as bool? ?? false,
        bounceBack: j['bounceBack'] as bool? ?? false,
        turnSeconds: (j['turnSeconds'] as num?)?.toInt() ?? 30,
      );
}

/// Complete, serialisable game state. Fields are mutable only so the engine can
/// edit a private copy; everything outside the engine treats it as read-only.
class GameState {
  final GameConfig config;

  /// tokens[seat][index] = progress (see [BoardLayout]).
  final List<List<int>> tokens;
  int currentSeat;
  LudoPhase phase;

  /// Last value rolled (0 before the first roll).
  int dice;
  int rollCount;
  int turnCount;

  /// Team ids in finishing order (index 0 = winner).
  final List<int> ranking;

  /// presence[seat]: whether the seat is still playing (see [SeatPresence]).
  final List<SeatPresence> presence;

  /// missed[seat]: consecutive turn timeouts of the seat (online games).
  final List<int> missed;

  /// Consecutive 6s rolled by the current seat in this turn.
  int sixStreak;

  GameState({
    required this.config,
    required this.tokens,
    required this.currentSeat,
    required this.phase,
    required this.dice,
    required this.rollCount,
    required this.turnCount,
    required this.ranking,
    List<SeatPresence>? presence,
    List<int>? missed,
    this.sixStreak = 0,
  })  : presence = presence ??
            List<SeatPresence>.filled(config.playerCount, SeatPresence.active),
        missed = missed ?? List<int>.filled(config.playerCount, 0);

  GameState copy() => GameState(
        config: config,
        tokens: tokens.map((t) => List<int>.of(t)).toList(),
        currentSeat: currentSeat,
        phase: phase,
        dice: dice,
        rollCount: rollCount,
        turnCount: turnCount,
        ranking: List<int>.of(ranking),
        presence: List<SeatPresence>.of(presence),
        missed: List<int>.of(missed),
        sixStreak: sixStreak,
      );

  int teamOf(int seat) => config.teams[seat];

  bool isActive(int seat) => presence[seat] == SeatPresence.active;

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'tokens': tokens,
        'seat': currentSeat,
        'phase': phase.index,
        'dice': dice,
        'rolls': rollCount,
        'turns': turnCount,
        'ranking': ranking,
        'presence': presence.map((p) => p.index).toList(),
        'missed': missed,
        'sixes': sixStreak,
      };

  factory GameState.fromJson(Map<String, dynamic> j) {
    final cfg = GameConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map));
    final toks = (j['tokens'] as List)
        .map((r) => (r as List).map((e) => (e as num).toInt()).toList())
        .toList();
    if (toks.length != cfg.playerCount || toks.any((t) => t.length != cfg.tokenCount)) {
      throw const FormatException('Token table does not match the player count');
    }
    return GameState(
      config: cfg,
      tokens: toks,
      currentSeat: (j['seat'] as num).toInt(),
      phase: LudoPhase.values[(j['phase'] as num).toInt()],
      dice: (j['dice'] as num).toInt(),
      rollCount: (j['rolls'] as num).toInt(),
      turnCount: (j['turns'] as num).toInt(),
      ranking: (j['ranking'] as List).map((e) => (e as num).toInt()).toList(),
      // Older saves / rooms have neither field: everybody is active.
      presence: (j['presence'] as List?)
          ?.map((e) => SeatPresence.values[(e as num).toInt()])
          .toList(),
      missed: (j['missed'] as List?)?.map((e) => (e as num).toInt()).toList(),
      sixStreak: (j['sixes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Everything two players must agree on before Quick Start may put them in the
/// same game. Two criteria match only when [key]s are identical, i.e. the same
/// player count, team layout and every game rule.
class MatchCriteria {
  final int playerCount;

  /// Index into BoardLayout.teamPresets, or -1 for no teams.
  final int teamPreset;
  final bool bonusOnCapture;
  final bool bonusOnFinish;
  final bool bonusOnOne;
  final bool enterOnOne;
  final bool rankAll;

  /// Tokens per player (1-4).
  final int tokenCount;

  /// One token per player starts already out of the yard.
  final bool oneTokenOut;
  final bool stackedCapture;
  final bool threeSixesForfeit;
  final bool bounceBack;

  /// Seconds allowed per move online; 0 = no limit.
  final int turnSeconds;

  const MatchCriteria({
    required this.playerCount,
    required this.teamPreset,
    required this.bonusOnCapture,
    required this.bonusOnFinish,
    required this.bonusOnOne,
    required this.enterOnOne,
    required this.rankAll,
    this.tokenCount = 4,
    this.oneTokenOut = false,
    this.stackedCapture = true,
    this.threeSixesForfeit = true,
    this.bounceBack = false,
    this.turnSeconds = 30,
  });

  static String _b(bool v) => v ? '1' : '0';

  String get key => 'p$playerCount|t$teamPreset|c${_b(bonusOnCapture)}'
      '|f${_b(bonusOnFinish)}|o${_b(bonusOnOne)}|e${_b(enterOnOne)}|r${_b(rankAll)}|k$tokenCount|x${_b(oneTokenOut)}'
      '|sc${_b(stackedCapture)}|ts${_b(threeSixesForfeit)}|bb${_b(bounceBack)}|tm$turnSeconds';

  /// Short human readable summary, e.g. for lobby chips.
  List<String> get labels => [
        '$playerCount players',
        if (teamPreset >= 0) 'Teams',
        if (tokenCount != 4) '$tokenCount token${tokenCount == 1 ? '' : 's'} each',
        if (bonusOnCapture) 'Roll again on capture',
        if (bonusOnFinish) 'Roll again on home',
        if (bonusOnOne) 'Roll again on 1',
        if (enterOnOne) '1 leaves yard',
        if (oneTokenOut) 'One token out',
        if (!stackedCapture) 'Stacks are safe',
        if (threeSixesForfeit) 'Three 6s forfeit',
        if (bounceBack) 'Bounce back',
        turnSeconds == 0 ? 'No time limit' : '${turnSeconds}s per move',
        if (!rankAll) 'First to finish wins',
      ];

  @override
  bool operator ==(Object other) => other is MatchCriteria && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
