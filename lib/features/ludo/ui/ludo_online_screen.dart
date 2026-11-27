import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lan_backend.dart';
import '../data/online_repository.dart';
import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import 'ludo_game_screen.dart';
import 'ludo_theme.dart';

/// Which online flow a [LudoOnlineScreen] runs.
enum OnlineEntry {
  /// Search for players who chose exactly the same player count and rules.
  quick,

  /// Create a private room and share its code. The creator is the host.
  create,

  /// Join a private room with a code.
  join,

  /// Host a room on the local network (hotspot / Wi-Fi). No internet needed.
  lanHost,

  /// Find rooms hosted on the local network and join one.
  lanJoin,
}

/// Settings chosen on the setup screen that a new online room is created with.
class OnlineSettings {
  final String hostName;
  final int playerCount;

  /// Index into BoardLayout.teamPresets, or -1 for no teams.
  final int teamPreset;
  final bool bonusOnCapture;
  final bool bonusOnFinish;
  final bool bonusOnOne;
  final bool enterOnOne;
  final bool rankAll;
  final int tokenCount;
  final bool oneTokenOut;
  final bool stackedCapture;
  final bool threeSixesForfeit;
  final bool bounceBack;

  /// Seconds per move; 0 = no limit.
  final int turnSeconds;

  const OnlineSettings({
    required this.hostName,
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

  MatchCriteria get criteria => MatchCriteria(
        playerCount: playerCount,
        teamPreset: teamPreset,
        bonusOnCapture: bonusOnCapture,
        bonusOnFinish: bonusOnFinish,
        bonusOnOne: bonusOnOne,
        enterOnOne: enterOnOne,
        rankAll: rankAll,
        tokenCount: tokenCount,
        oneTokenOut: oneTokenOut,
        stackedCapture: stackedCapture,
        threeSixesForfeit: threeSixesForfeit,
        bounceBack: bounceBack,
        turnSeconds: turnSeconds,
      );
}

/// Quick Start search, private room lobby, or join-by-code.
class LudoOnlineScreen extends ConsumerStatefulWidget {
  const LudoOnlineScreen({super.key, required this.entry, this.settings})
      : assert(entry == OnlineEntry.join || entry == OnlineEntry.lanJoin || settings != null,
            'quick, create and lanHost need settings');

  final OnlineEntry entry;
  final OnlineSettings? settings;

  @override
  ConsumerState<LudoOnlineScreen> createState() => _LudoOnlineScreenState();
}

class _LudoOnlineScreenState extends ConsumerState<LudoOnlineScreen> {
  final TextEditingController _code = TextEditingController();

  String? _roomCode;
  bool _isHost = false;
  String? _uid;
  RoomData? _room;
  List<RoomMember> _members = const [];
  StreamSubscription<RoomData>? _roomSub;
  StreamSubscription<List<RoomMember>>? _memberSub;
  Timer? _timer;
  int _tick = 0;
  bool _busy = false;
  bool _launched = false;
  bool _autoStarted = false;
  bool _merging = false;
  bool _showRules = false; // private-room rules section, collapsed by default
  bool _wasMember = false; // guest: our member record has been seen in the lobby
  String? _error;

  // Wi-Fi / hotspot join: rooms found on the network, plus a typed address.
  final TextEditingController _addr = TextEditingController();
  StreamSubscription<List<LanRoomInfo>>? _scanSub;
  List<LanRoomInfo> _found = const [];
  String? _scanError;

  bool get _quick => widget.entry == OnlineEntry.quick;
  bool get _lan => widget.entry == OnlineEntry.lanHost || widget.entry == OnlineEntry.lanJoin;
  bool get _isJoinEntry => widget.entry == OnlineEntry.join || widget.entry == OnlineEntry.lanJoin;

  /// The room service in use: Firestore, or the local-network host.
  RoomBackend get _repo =>
      _lan ? ref.read(lanBackendProvider) : ref.read(onlineRepoProvider);

  /// Firestore-only features (Quick Start matchmaking).
  LudoOnlineRepository get _fb => ref.read(onlineRepoProvider);

  @override
  void initState() {
    super.initState();
    _busy = !_isJoinEntry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.entry == OnlineEntry.quick) _quickSearch();
      if (widget.entry == OnlineEntry.create || widget.entry == OnlineEntry.lanHost) _create();
      if (widget.entry == OnlineEntry.lanJoin) _startScan();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _roomSub?.cancel();
    _memberSub?.cancel();
    _scanSub?.cancel();
    _addr.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _playerName {
    final t = (ref.read(playerNameProvider).valueOrNull ?? widget.settings?.hostName ?? '').trim();
    return t.isEmpty ? 'Player' : (t.length > 12 ? t.substring(0, 12) : t);
  }

  // ------------------------------------------------------------------ actions

  /// Turns any exception into a short, readable message. Raw Firestore /
  /// network errors are never shown to the player.
  String _friendly(Object e) {
    const offline = 'No internet connection. Please check your connection and try again.';
    final raw = e.toString().toLowerCase();
    if (e is RoomException) {
      if (raw.contains('sign in')) return offline;
      return e.message;
    }
    if (raw.contains('unavailable') ||
        raw.contains('network') ||
        raw.contains('offline') ||
        raw.contains('socket') ||
        raw.contains('host lookup') ||
        raw.contains('unable to resolve') ||
        raw.contains('deadline') ||
        raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('connection')) {
      return offline;
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _guard(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _requireFirebase() {
    if (_lan) return;
    if (!LudoOnlineRepository.isAvailable) {
      throw RoomException('Firebase is not configured. See the README for setup.');
    }
  }

  /// Quick Start: join the oldest open lobby with exactly our criteria, or
  /// open a new public lobby and wait for others to find it.
  Future<void> _quickSearch() => _guard(() async {
        _requireFirebase();
        final criteria = widget.settings!.criteria;
        _autoStarted = false;
        final found = await _fb.quickJoin(criteria, _playerName);
        final uid = await _repo.signIn();
        if (!mounted) {
          if (found != null) await _repo.leaveRoom(found.code);
          return;
        }
        if (found != null) {
          _enterLobby(found.code, host: false, uid: uid);
          return;
        }
        final code = await _repo.createRoom(
          hostName: _playerName,
          criteria: criteria,
          quick: true,
        );
        if (!mounted) {
          await _repo.closeRoom(code);
          return;
        }
        _enterLobby(code, host: true, uid: uid);
      });

  Future<void> _create() => _guard(() async {
        _requireFirebase();
        final s = widget.settings!;
        final code = await _repo.createRoom(
          hostName: _playerName,
          criteria: s.criteria,
        );
        final uid = await _repo.signIn();
        if (!mounted) {
          await _repo.closeRoom(code);
          return;
        }
        _enterLobby(code, host: true, uid: uid);
      });

  Future<void> _join() => _guard(() async {
        _requireFirebase();
        final raw = _code.text.trim();
        if (raw.length != 6) throw RoomException('Room codes have 6 characters');
        final room = await _repo.joinRoom(raw, _playerName);
        final uid = await _repo.signIn();
        _enterLobby(room.code, host: false, uid: uid);
      });

  void _startScan() {
    _scanSub?.cancel();
    setState(() {
      _found = const [];
      _scanError = null;
    });
    _scanSub = LanDiscovery().scan().listen((rooms) {
      if (mounted) setState(() => _found = rooms);
    }, onError: (Object e) {
      if (mounted) setState(() => _scanError = 'Could not search this network: $e');
    });
  }

  /// Wi-Fi: join a host found on the network, or one typed by address.
  Future<void> _joinLan(String address) => _guard(() async {
        final room = await _repo.joinRoom(address, _playerName);
        final uid = await _repo.signIn();
        _scanSub?.cancel();
        _scanSub = null;
        _enterLobby(room.code, host: false, uid: uid);
      });

  void _enterLobby(String code, {required bool host, required String uid}) {
    _launched = false;
    _autoStarted = false;
    _wasMember = false;
    _tick = 0;
    _roomSub?.cancel();
    _memberSub?.cancel();
    _timer?.cancel();
    setState(() {
      _roomCode = code;
      _isHost = host;
      _uid = uid;
      _room = null;
      _members = const [];
    });
    _memberSub = _repo.watchMembers(code).listen((m) {
      if (!mounted) return;
      setState(() => _members = m);
      _checkRemoved(m);
      _maybeAutoStart();
    }, onError: (_) {});
    _roomSub = _repo.watchRoom(code).listen(_onRoom, onError: (e) {
      if (mounted) setState(() => _error = _friendly(e));
    });
    if (_quick) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _quickTick());
    }
  }

  void _onRoom(RoomData room) {
    if (!mounted) return;
    setState(() => _room = room);
    if (room.status == 'closed' && !_isHost && !_launched) {
      if (_quick) {
        _requeue(); // the lobby we were in vanished: look for another match
      } else {
        _leaveLobby(message: 'The host closed the room');
      }
      return;
    }
    if (!_isHost && room.status == 'playing' && room.stateJson != null && !_launched) {
      try {
        final initial =
            GameState.fromJson(Map<String, dynamic>.from(jsonDecode(room.stateJson!) as Map));
        _launch(initial, room.version);
      } catch (e) {
        setState(() => _error = 'Could not read the game state: $e');
      }
    }
    _maybeAutoStart();
  }

  /// Private-room guest: the host removed us if our member record vanished.
  void _checkRemoved(List<RoomMember> members) {
    if (_isHost || _quick || _launched || _busy) return;
    final status = _room?.status;
    if (status == 'closed' || status == 'playing' || status == 'finished') return;
    final present = members.any((m) => m.uid == _uid);
    if (present) {
      _wasMember = true;
    } else if (_wasMember) {
      _wasMember = false;
      _leaveLobby(message: 'The host removed you from the room');
    }
  }

  /// Host: seats a bot of [level] in the first open seat.
  Future<void> _addBot(BotLevel level) => _guard(() async {
        final code = _roomCode;
        if (code == null) return;
        final used = _members.where((m) => m.isBot).map((m) => m.name).toSet();
        var n = 1;
        while (used.contains('Bot $n')) {
          n++;
        }
        await _repo.addBot(code, 'Bot $n', level);
      });

  /// Host: removes a bot or kicks a joined player.
  Future<void> _removeMember(RoomMember m) => _guard(() async {
        final code = _roomCode;
        if (code == null) return;
        await _repo.removeMember(code, m.uid);
      });

  static String _levelName(BotLevel l) => switch (l) {
        BotLevel.easy => 'Easy',
        BotLevel.medium => 'Medium',
        BotLevel.hard => 'Hard',
      };

  /// Quick Start hosts start the match by themselves once every seat is taken.
  void _maybeAutoStart() {
    if (!_quick || !_isHost || _autoStarted || _launched) return;
    final count = _room?.playerCount ?? widget.settings!.playerCount;
    if (_room != null && _members.length >= count) {
      _autoStarted = true;
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (mounted && !_launched) _start();
      });
    }
  }

  /// Every 4 seconds while in a Quick Start lobby:
  ///  - host: heartbeat, and if still alone, merge into an older matching lobby;
  ///  - guest: leave and search again if the host stopped answering.
  Future<void> _quickTick() async {
    if (!mounted || _launched || _roomCode == null || _busy) return;
    _tick++;
    final room = _room;
    if (_isHost) {
      if (_tick % 5 == 1) unawaited(_fb.pingRoom(_roomCode!));
      if (room != null && _members.length == 1 && !_merging) {
        _merging = true;
        try {
          final target = await _fb.findOlderQuickRoom(room);
          if (target != null && mounted && _members.length == 1 && !_launched) {
            final old = _roomCode!;
            final uid = _uid!;
            await _repo.joinRoom(target.code, _playerName, requireMatchKey: room.matchKey);
            _roomSub?.cancel();
            _memberSub?.cancel();
            await _repo.closeRoom(old);
            if (mounted) _enterLobby(target.code, host: false, uid: uid);
          }
        } catch (_) {
          // The other lobby filled up meanwhile; just keep waiting here.
        } finally {
          _merging = false;
        }
      }
    } else if (room != null && !room.isHostAlive(DateTime.now())) {
      _requeue();
    }
  }

  Future<void> _requeue() async {
    if (_busy) return;
    await _teardown();
    if (!mounted) return;
    setState(() {
      _roomCode = null;
      _room = null;
      _members = const [];
    });
    await _quickSearch();
  }

  Future<void> _start() => _guard(() async {
        final room = _room;
        final uid = _uid;
        final code = _roomCode;
        if (room == null || uid == null || code == null) return;
        // Never start a short room: every seat is a player or a bot the host added.
        if (_members.length < room.playerCount) {
          _autoStarted = false;
          return;
        }
        final layout = BoardLayout.forPlayers(room.playerCount);
        final seats = <SeatConfig>[
          for (var i = 0; i < room.playerCount; i++)
            _members[i].isBot
                ? SeatConfig(name: _members[i].name, kind: PlayerKind.bot, level: _members[i].level)
                : SeatConfig(name: _members[i].name, uid: _members[i].uid),
        ];
        final teams = room.teamPreset >= 0 && room.teamPreset < layout.teamPresets.length
            ? layout.teamPresets[room.teamPreset].teamOfSeat
            : null;
        final config = GameConfig(
          seats: seats,
          teams: teams,
          bonusOnCapture: room.bonusOnCapture,
          bonusOnFinish: room.bonusOnFinish,
          bonusOnOne: room.bonusOnOne,
          enterOnOne: room.enterOnOne,
          rankAll: room.rankAll,
          tokenCount: room.tokenCount,
          oneTokenOut: room.oneTokenOut,
          stackedCapture: room.stackedCapture,
          threeSixesForfeit: room.threeSixesForfeit,
          bounceBack: room.bounceBack,
          turnSeconds: room.turnSeconds,
        );
        final initial = LudoEngine.newGame(config);
        await _repo.startGame(
          code,
          initial,
          botIds: [for (final m in _members.take(room.playerCount)) if (m.isBot) m.uid],
        );
        _launch(initial, 1);
      });

  void _launch(GameState initial, int version) {
    final code = _roomCode;
    final uid = _uid;
    if (code == null || uid == null || _launched) return;
    _launched = true;
    _timer?.cancel();
    ref.read(ludoControllerProvider.notifier).attachOnline(
          backend: _repo,
          code: code,
          uid: uid,
          host: _isHost,
          initial: initial,
          version: version,
          quick: _quick,
        );
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LudoGameScreen()))
        .then((_) {
      // Back from the game: the controller already left / closed the room.
      if (!mounted) return;
      _roomSub?.cancel();
      _memberSub?.cancel();
      // Skip if we were already popped (e.g. results → "Back to menu" went
      // straight to the home screen); otherwise we'd pop the home screen.
      if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
    });
  }

  /// Stops listening and frees our seat (guest) or closes the lobby (host).
  Future<void> _teardown() async {
    final code = _roomCode;
    final host = _isHost;
    _timer?.cancel();
    await _roomSub?.cancel();
    await _memberSub?.cancel();
    _roomSub = null;
    _memberSub = null;
    if (code != null) {
      try {
        if (host) {
          await _repo.closeRoom(code);
        } else {
          await _repo.leaveRoom(code);
        }
      } catch (_) {}
    }
  }

  Future<void> _leaveLobby({String? message}) async {
    await _teardown();
    if (!mounted) return;
    if (_isJoinEntry) {
      setState(() {
        _roomCode = null;
        _room = null;
        _members = const [];
        _error = message;
      });
      if (widget.entry == OnlineEntry.lanJoin) _startScan();
    } else {
      Navigator.of(context).pop();
    }
  }

  // ----------------------------------------------------------------------- UI

  /// Host-side entries that show "Creating your room…" before the lobby opens.
  bool get _creating =>
      widget.entry == OnlineEntry.create || widget.entry == OnlineEntry.lanHost;

  String get _title => switch (widget.entry) {
        OnlineEntry.quick => 'Quick Start',
        OnlineEntry.create => 'Private room',
        OnlineEntry.join => 'Join a room',
        OnlineEntry.lanHost => 'Wi-Fi room',
        OnlineEntry.lanJoin => 'Join a Wi-Fi room',
      };

  @override
  Widget build(BuildContext context) {
    final inLobby = _roomCode != null;
    return PopScope(
      canPop: !inLobby,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveLobby();
      },
      child: LudoScaffold(
        title: Text(_title),
        body: SafeArea(
          child: (_quick && (inLobby || _busy)) || (_creating && !inLobby && _busy)
              ? _quickWaiting(context)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_error != null) _errorCard(context),
                        if (inLobby)
                          ..._lobby(context)
                        else if (widget.entry == OnlineEntry.lanJoin)
                          ..._lanJoinForm(context)
                        else if (widget.entry == OnlineEntry.join)
                          ..._joinForm(context)
                        else
                          ..._starting(context),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
        ),
      );

  /// Quick Start: just a centred loading screen while searching, no lobby or
  /// player list. The game opens by itself once the match is complete.
  Widget _quickWaiting(BuildContext context) {
    final theme = Theme.of(context);
    final found = _roomCode != null &&
        _members.length >= (_room?.playerCount ?? widget.settings!.playerCount);
    return Column(
      children: [
        if (_error != null)
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: _errorCard(context)),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: found
                        ? const Icon(Icons.check_circle_rounded, size: 84, color: LudoPalette.gold)
                        : const CircularProgressIndicator(strokeWidth: 6),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    found
                        ? 'Match found!'
                        : (_quick ? 'Looking for opponent…' : 'Creating your room…'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _launched || found
                        ? null
                        : () {
                            if (_roomCode != null) {
                              _leaveLobby();
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Shown while a Quick Start search or room creation is in flight (or failed).
  List<Widget> _starting(BuildContext context) {
    return [
      LudoPanel(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),
              if (_busy)
                const CircularProgressIndicator()
              else
                const Icon(Icons.cloud_off_rounded, size: 40),

              const SizedBox(height: 16),

              Text(
                _busy
                    ? (_quick ? 'Looking for a match…' : 'Creating your room…')
                    : 'Could not connect',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),

              const SizedBox(height: 16),

              if (!_busy)
                FilledButton.icon(
                  onPressed: _quick ? _quickSearch : _create,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _lanJoinForm(BuildContext context) {
    final theme = Theme.of(context);
    return [
      LudoPanel(
        title: 'Rooms on this network',
        icon: Icons.wifi_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Connect to the host\'s hotspot or the same Wi-Fi, and their room shows up here.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (_scanError != null)
              Text(_scanError!, style: TextStyle(color: theme.colorScheme.error))
            else if (_found.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    SizedBox(width: 12),
                    Text('Searching for rooms…'),
                  ],
                ),
              ),
            for (final r in _found)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: LudoPalette.accent,
                    child: Icon(Icons.wifi_tethering_rounded, color: Colors.white),
                  ),
                  title: Text("${r.hostName}'s room"),
                  subtitle: Text('${r.players} / ${r.capacity} players'
                      .replaceAll(RegExp(r' · $'), '')),
                  trailing: FilledButton(
                    onPressed: _busy || r.isFull ? null : () => _joinLan(r.address),
                    child: Text(r.isFull ? 'Full' : 'Join'),
                  ),
                ),
              ),
          ],
        ),
      ),
      LudoPanel(
        title: 'Enter host address',
        icon: Icons.keyboard_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Room not listed? Type the address shown on the host\'s screen.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _addr,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '192.168.43.1:45679'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _busy ? null : () => _joinLan(_addr.text),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Join'),
            ),
            if (_busy)
              const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    ];
  }

  List<Widget> _joinForm(BuildContext context) {
    return [
      LudoPanel(
        title: 'Room code',
        icon: Icons.vpn_key_rounded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _code,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(counterText: '', hintText: 'ABC123'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _busy ? null : _join,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Join room'),
            ),
            if (_busy)
              const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    ];
  }

  Widget _chips(MatchCriteria c) => Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [for (final l in c.labels) Chip(label: Text(l), visualDensity: VisualDensity.compact)],
      );

  /// Collapsible summary of the rules the host chose.
  /// Hidden by default for everyone; tap the header to expand or collapse.
  Widget _rulesSection(BuildContext context, MatchCriteria? criteria) {
    if (criteria == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final presets = BoardLayout.forPlayers(criteria.playerCount).teamPresets;
    final teamsOn = presets.isNotEmpty && criteria.teamPreset >= 0 && criteria.teamPreset < presets.length;
    final rules = <_RuleRow>[
      if (presets.isEmpty)
        const _RuleRow('Team mode', false, status: 'N/A', detail: 'Not available with this player count')
      else
        _RuleRow('Team mode', teamsOn, detail: teamsOn ? presets[criteria.teamPreset].label : null),
      _RuleRow('Tokens per player', true, status: '${criteria.tokenCount}'),
      _RuleRow('Roll again after a capture', criteria.bonusOnCapture),
      _RuleRow('Roll again after a token reaches home', criteria.bonusOnFinish),
      _RuleRow('Roll again after rolling a 1', criteria.bonusOnOne, detail: 'A 6 always gives another roll'),
      _RuleRow('A 1 also brings a token out of the yard', criteria.enterOnOne, detail: 'Normally only a 6 does'),
      _RuleRow('One Token Out', criteria.oneTokenOut, detail: 'Every player starts with one token already out'),
      _RuleRow('Stacked capture', criteria.stackedCapture, detail: 'Two or more opponent tokens on a square are all captured'),
      _RuleRow('Three sixes forfeit', criteria.threeSixesForfeit, detail: 'Three 6s in a row end the turn with no move'),
      _RuleRow('Bounce back at home', criteria.bounceBack, detail: 'Overshooting home bounces the token back'),
      _RuleRow('Play on until every rank is decided', criteria.rankAll),
      _RuleRow(
        'Time per move',
        true,
        status: criteria.turnSeconds == 0 ? 'No limit' : '${criteria.turnSeconds}s',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _showRules = !_showRules),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.rule_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  _showRules ? 'Hide game rules' : 'Show game rules',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _showRules ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _showRules
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    children: [
                      for (final r in rules)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                r.on ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                size: 20,
                                color: r.on ? Colors.greenAccent : Colors.white38,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.title, style: theme.textTheme.bodyMedium),
                                    if (r.detail != null)
                                      Text(r.detail!, style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                r.status ?? (r.on ? 'On' : 'Off'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: r.on ? Colors.greenAccent : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Right side of a lobby seat. Only the host of a private room gets controls:
  /// "add bot" on open seats, "remove" on bots and on joined players.
  Widget _seatTrailing(int i) {
    final taken = i < _members.length;
    if (_isHost && !_quick) {
      if (!taken) {
        return PopupMenuButton<BotLevel>(
          enabled: !_busy && _room != null,
          tooltip: 'Add a bot',
          onSelected: _addBot,
          itemBuilder: (_) => [
            for (final l in BotLevel.values)
              PopupMenuItem(value: l, child: Text('${_levelName(l)} bot')),
          ],
          child: const Chip(
            avatar: Icon(Icons.smart_toy_rounded, size: 18),
            label: Text('Add bot'),
            visualDensity: VisualDensity.compact,
          ),
        );
      }
      final m = _members[i];
      if (m.uid != _uid) {
        return IconButton(
          tooltip: m.isBot ? 'Remove bot' : 'Remove player',
          icon: const Icon(Icons.person_remove_rounded),
          color: Colors.red.shade300,
          onPressed: _busy ? null : () => _removeMember(m),
        );
      }
    }
    return Icon(taken ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded);
  }

  List<Widget> _lobby(BuildContext context) {
    final room = _room;
    final count = room?.playerCount ?? widget.settings?.playerCount ?? 4;
    final layout = BoardLayout.forPlayers(count);
    final teamMap = room != null && room.teamPreset >= 0 && room.teamPreset < layout.teamPresets.length
        ? layout.teamPresets[room.teamPreset].teamOfSeat
        : null;
    final full = _members.length >= count;
    final theme = Theme.of(context);

    return [
      if (_quick)
        LudoPanel(
          child: Column(
            children: [
              Text(
                full ? 'Match found!' : 'Waiting for players…',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                full
                    ? 'Starting the game…'
                    : '${_members.length} of $count joined. Only players with the same player count and rules are matched.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: full ? 1 : null,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 14),
              if (room != null) _chips(room.criteria) else _chips(widget.settings!.criteria),
            ],
          ),
        )
      else
        LudoPanel(
          child: Column(
            children: [
              Text(_lan ? 'Wi-Fi room' : 'Room code'),
              SelectableText(
                _lan ? (ref.read(lanBackendProvider).address ?? _roomCode!) : _roomCode!,
                style: _lan
                    ? theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)
                    : theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6),
              ),
              Text(_quick
                  ? 'Waiting for the match to start…'
                  : (_isHost
                      ? (_lan
                          ? 'Friends on your hotspot / Wi-Fi see this room automatically, or can type this address'
                          : 'Share this code with your friends')
                      : 'Waiting for the host to start…'),
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.groups_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Players joined: ${_members.length} / $count',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _rulesSection(context, room?.criteria ?? widget.settings?.criteria),
            ],
          ),
        ),
      for (var i = 0; i < count; i++)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: LudoPalette.seat(layout.colorIndexOfSeat(i)),
              child: i < _members.length && _members[i].isBot
                  ? const Icon(Icons.smart_toy_rounded, color: Colors.white)
                  : (teamMap == null
                      ? null
                      : Text(LudoPalette.teamName(teamMap[i]), style: const TextStyle(color: Colors.white))),
            ),
            title: Text(i < _members.length
                ? (_members[i].uid == _uid ? '${_members[i].name} (you)' : _members[i].name)
                : (_quick ? 'Searching…' : 'Open seat')),
            subtitle: Text(i < _members.length
                ? (_members[i].isBot
                    ? 'Bot · ${_levelName(_members[i].level)}'
                    : (_members[i].uid == room?.hostUid || (i == 0 && !_quick) ? 'Host' : 'Joined'))
                : (_quick
                    ? 'Waiting for a matching player'
                    : (_isHost ? 'Waiting for a player, or add a bot' : 'Waiting for a player to join'))),
            trailing: _seatTrailing(i),
          ),
        ),
      const SizedBox(height: 12),
      if (_isHost && !_quick)
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy || room == null || !full ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(full
              ? 'Start game'
              : 'Waiting for ${count - _members.length} more '
                  '${count - _members.length == 1 ? 'player' : 'players'}'),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _leaveLobby(),
        icon: Icon(_quick ? Icons.close_rounded : Icons.exit_to_app_rounded),
        label: Text(_quick ? 'Cancel search' : (_isHost ? 'Close room' : 'Leave room')),
      ),
    ];
  }
}

/// One line of the read-only rules list in the private room lobby.
class _RuleRow {
  const _RuleRow(this.title, this.on, {this.detail, this.status});
  final String title;
  final bool on;
  final String? detail;
  final String? status;
}