import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../chat/quick_chat_catalog.dart';
import '../engine/engine.dart';
import 'online_repository.dart';
import 'quick_chat_event.dart';

/// Hotspot / local Wi-Fi multiplayer.
///
/// No internet and no Firebase are needed. The host's device runs a tiny
/// WebSocket server and is the authority for the room (lobby members, bots,
/// game state, versions); guests connect to it. While the room is in its lobby
/// the host announces it with UDP broadcasts so that other devices on the same
/// network can list it ([LanDiscovery]); a guest can also type the host's
/// address by hand.
///
/// The class implements the same [RoomBackend] as the Firestore repository,
/// so the lobby screen and the game controller work unchanged.
class LanBackend implements RoomBackend {
  static const defaultPort = 45679;

  /// This install's identity for the current app run (no sign-in needed).
  static final String _uid = 'lan_${_randomId(10)}';

  _HostSession? _host;
  _ClientSession? _client;

  /// "ip:port" of the room this device hosts or has joined (null if none).
  String? get address => _host?.address ?? _client?.address;

  @override
  Future<String> signIn() async => _uid;

  _Session? _session(String code) {
    if (_host != null && _host!.code == code) return _host;
    if (_client != null && _client!.code == code) return _client;
    return null;
  }

  @override
  Future<String> createRoom({
    required String hostName,
    required MatchCriteria criteria,
    bool quick = false,
  }) async {
    await _dispose();
    final code = _randomId(6).toUpperCase();
    final host = _HostSession(code, _uid, hostName, criteria);
    try {
      await host.start();
    } catch (e) {
      await host.shutdown();
      throw RoomException('Could not start the room on this network: $e');
    }
    _host = host;
    return code;
  }

  /// [code] is the host's address, "ip" or "ip:port" (from the room list or
  /// typed by hand). The returned room carries the real room code.
  @override
  Future<RoomData> joinRoom(String code, String name, {String? requireMatchKey}) async {
    await _dispose();
    final addr = code.trim();
    final parts = addr.split(':');
    final port = parts.length > 1 ? int.tryParse(parts[1]) : defaultPort;
    if (parts[0].isEmpty || port == null) {
      throw RoomException('Enter the host address like 192.168.43.1 or 192.168.43.1:45679');
    }
    final client = _ClientSession(parts[0], port, _uid);
    try {
      final room = await client.connect(name);
      _client = client;
      return room;
    } catch (e) {
      await client.close();
      if (e is RoomException) rethrow;
      throw RoomException('Could not reach the host at $addr. Are you on the same Wi-Fi or hotspot?');
    }
  }

  Future<void> _dispose() async {
    final h = _host;
    final c = _client;
    _host = null;
    _client = null;
    await h?.shutdown();
    await c?.close();
  }

  @override
  Stream<RoomData> watchRoom(String code) => _session(code)?.roomStream ?? const Stream.empty();

  @override
  Stream<List<RoomMember>> watchMembers(String code) =>
      _session(code)?.membersStream ?? const Stream.empty();

  @override
  Future<RoomData?> getRoom(String code) async => _session(code)?.currentRoom;

  @override
  Future<void> startGame(String code, GameState initial, {List<String> botIds = const []}) async {
    final h = _host;
    if (h == null || h.code != code) throw RoomException('Only the host can start the game');
    h.startGame(initial);
  }

  @override
  Future<void> addBot(String code, String name, BotLevel level) async {
    final h = _host;
    if (h == null || h.code != code) throw RoomException('Only the host can add bots');
    h.addBot(name, level);
  }

  @override
  Future<void> removeMember(String code, String memberId) async {
    final h = _host;
    if (h == null || h.code != code) throw RoomException('Only the host can remove players');
    await h.removeMember(memberId);
  }

  @override
  Future<bool> publishStateCas(
      String code, GameState state, int baseVersion, int newVersion) async {
    final s = _session(code);
    if (s == null) return false;
    return s.publishState(state, baseVersion, newVersion);
  }

  @override
  Future<void> leaveGame(String code, int? seat) async {
    final s = _session(code);
    if (s == null) return;
    await s.leaveGame(seat);
    _forgetIfDone(s);
  }

  @override
  Future<void> leaveRoom(String code) async {
    final s = _session(code);
    if (s == null) return;
    await s.leaveLobby();
    _forgetIfDone(s);
  }

  @override
  Future<void> closeRoom(String code) async {
    final h = _host;
    if (h == null || h.code != code) return;
    await h.closeRoom();
  }

  @override
  Future<void> sendQuickChat(String code, String itemId) async {
    final s = _session(code);
    if (s == null) throw RoomException('You are not connected to a room');
    await s.sendChat(itemId);
  }

  @override
  Stream<QuickChatEvent> watchQuickChat(String code) =>
      _session(code)?.chatStream ?? const Stream.empty();

  void _forgetIfDone(_Session s) {
    if (s is _ClientSession) {
      if (identical(_client, s)) _client = null;
    } else if (s is _HostSession && s.isShutDown && identical(_host, s)) {
      _host = null;
    }
  }
}

String _randomId(int n) {
  const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = math.Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

/// A broadcast stream that hands the latest value to every new listener.
class _Replay<T> {
  final StreamController<T> _c = StreamController<T>.broadcast();
  T? last;
  bool has = false;

  void add(T v) {
    last = v;
    has = true;
    if (!_c.isClosed) _c.add(v);
  }

  Stream<T> get stream => Stream<T>.multi((ctl) {
        if (has) ctl.add(last as T);
        final sub = _c.stream.listen(ctl.add);
        ctl.onCancel = sub.cancel;
      });
}

abstract class _Session {
  String get code;
  Stream<RoomData> get roomStream;
  Stream<List<RoomMember>> get membersStream;
  RoomData? get currentRoom;
  Future<bool> publishState(GameState state, int baseVersion, int newVersion);
  Future<void> leaveGame(int? seat);
  Future<void> leaveLobby();

  /// Quick chat events of this room (every player's, the local one included).
  Stream<QuickChatEvent> get chatStream;
  Future<void> sendChat(String itemId);
}

List<Map<String, dynamic>> _membersToJson(List<RoomMember> ms) => [
      for (final m in ms)
        {'uid': m.uid, 'name': m.name, 'bot': m.isBot, 'level': m.level.index},
    ];

List<RoomMember> _membersFromJson(Object? raw) {
  final now = DateTime.now();
  final out = <RoomMember>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is! Map) continue;
      final uid = e['uid'] as String? ?? '';
      final lv = (e['level'] as num?)?.toInt() ?? BotLevel.medium.index;
      out.add(RoomMember(
        uid,
        e['name'] as String? ?? 'Player',
        now,
        isBot: uid.startsWith('bot_') && e['bot'] == true,
        level: BotLevel.values[lv.clamp(0, BotLevel.values.length - 1)],
      ));
    }
  }
  return out;
}

// ------------------------------------------------------------------- host side

class _HostSession implements _Session {
  _HostSession(this.code, this.hostUid, this.hostName, this.criteria);

  @override
  final String code;
  final String hostUid;
  final String hostName;
  final MatchCriteria criteria;

  String status = 'lobby';
  int version = 0;
  String? stateJson;
  final List<RoomMember> members = [];
  final Map<String, WebSocket> clients = {};

  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _announce;
  int _announceTick = 0;
  List<InternetAddress> _targets = const [];
  String _ip = '';
  bool _hostGone = false;
  bool isShutDown = false;

  final _Replay<RoomData> _room = _Replay<RoomData>();
  final _Replay<List<RoomMember>> _members = _Replay<List<RoomMember>>();

  final StreamController<QuickChatEvent> _chat = StreamController<QuickChatEvent>.broadcast();
  final Map<String, int> _lastChatMs = {};

  String get address => '$_ip:${_server?.port ?? LanBackend.defaultPort}';

  @override
  Stream<RoomData> get roomStream => _room.stream;
  @override
  Stream<List<RoomMember>> get membersStream => _members.stream;
  @override
  RoomData? get currentRoom => _room.last;

  Map<String, dynamic> _roomMap() => {
        'hostUid': hostUid,
        'status': status,
        'playerCount': criteria.playerCount,
        'teamPreset': criteria.teamPreset,
        'bonusOnCapture': criteria.bonusOnCapture,
        'bonusOnFinish': criteria.bonusOnFinish,
        'bonusOnOne': criteria.bonusOnOne,
        'enterOnOne': criteria.enterOnOne,
        'rankAll': criteria.rankAll,
        'tokenCount': criteria.tokenCount,
        'oneTokenOut': criteria.oneTokenOut,
        'stackedCapture': criteria.stackedCapture,
        'threeSixesForfeit': criteria.threeSixesForfeit,
        'bounceBack': criteria.bounceBack,
        'turnSeconds': criteria.turnSeconds,
        'version': version,
        if (stateJson != null) 'state': stateJson,
        'memberCount': members.length,
        'public': false,
      };

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, LanBackend.defaultPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server!.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        try {
          final ws = await WebSocketTransformer.upgrade(req);
          _onSocket(ws);
        } catch (_) {}
      } else {
        req.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
    members.add(RoomMember(hostUid, hostName, DateTime.now()));
    await _refreshAddresses();
    await _startAnnouncing();
    _emit();
  }

  Future<void> _refreshAddresses() async {
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
    String? best;
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          final p = a.address.split('.');
          if (p.length != 4) continue;
          // Dart exposes no netmask; phone hotspots and home routers use /24.
          targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
          final first = int.tryParse(p[0]) ?? 0;
          final second = int.tryParse(p[1]) ?? 0;
          final private = first == 10 ||
              (first == 192 && second == 168) ||
              (first == 172 && second >= 16 && second <= 31);
          if (best == null || (private && !_isPrivate(best))) best = a.address;
        }
      }
    } catch (_) {}
    _targets = targets;
    _ip = best ?? '0.0.0.0';
  }

  static bool _isPrivate(String ip) {
    final p = ip.split('.');
    final a = int.tryParse(p[0]) ?? 0;
    final b = int.tryParse(p[1]) ?? 0;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  Future<void> _startAnnouncing() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
    } catch (_) {
      _udp = null; // guests can still join by typing the address
    }
    _announce = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (isShutDown) return;
      if (++_announceTick % 10 == 0) await _refreshAddresses();
      final udp = _udp;
      if (udp == null || status != 'lobby') return;
      final data = utf8.encode(jsonEncode({
        'app': LanDiscovery.appId,
        'code': code,
        'host': hostName,
        'port': _server?.port ?? LanBackend.defaultPort,
        'room': _roomMap(),
      }));
      for (final t in _targets) {
        try {
          udp.send(data, t, LanDiscovery.port);
        } catch (_) {}
      }
    });
  }

  // ------------------------------------------------------------- broadcasting

  void _emit() {
    _room.add(RoomData.fromMap(code, _roomMap()));
    _members.add(List<RoomMember>.of(members));
    _sendAll({
      't': 'room',
      'room': _roomMap(),
      'members': _membersToJson(members),
    });
  }

  void _sendAll(Map<String, dynamic> msg) {
    final text = jsonEncode(msg);
    for (final ws in clients.values) {
      try {
        ws.add(text);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------- guest messages

  void _onSocket(WebSocket ws) {
    ws.pingInterval = const Duration(seconds: 5);
    String? who;
    ws.listen((data) {
      Map<String, dynamic> m;
      try {
        m = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
      } catch (_) {
        return;
      }
      switch (m['t']) {
        case 'join':
          who = _handleJoin(ws, m);
        case 'cas':
          if (who != null) _handleCas(ws, m);
        case 'leave':
          if (who != null) _removeGuest(who!, null);
        case 'leaveGame':
          if (who != null) _removeGuest(who!, (m['seat'] as num?)?.toInt());
        case 'chat':
          // The sender is the authenticated socket, never a field of the message.
          if (who != null) _relayChat(who!, m['item'], m['n']);
      }
    }, onDone: () {
      final id = who;
      if (id != null && identical(clients[id], ws)) _onDisconnect(id);
    }, onError: (_) {});
  }

  String? _handleJoin(WebSocket ws, Map<String, dynamic> m) {
    void fail(String msg) {
      ws.add(jsonEncode({'t': 'error', 'message': msg}));
      ws.close();
    }

    final uid = m['uid'] as String?;
    var name = (m['name'] as String? ?? 'Player').trim();
    if (uid == null || uid.isEmpty || uid.startsWith('bot_')) {
      fail('Invalid player');
      return null;
    }
    if (name.isEmpty) name = 'Player';
    if (name.length > 12) name = name.substring(0, 12);
    if (status != 'lobby') {
      fail('That game has already started');
      return null;
    }
    final idx = members.indexWhere((e) => e.uid == uid);
    if (idx >= 0) {
      members[idx] = RoomMember(uid, name, members[idx].joinedAt);
      try {
        clients[uid]?.close();
      } catch (_) {}
    } else {
      if (members.length >= criteria.playerCount) {
        fail('The room is full');
        return null;
      }
      members.add(RoomMember(uid, name, DateTime.now()));
    }
    clients[uid] = ws;
    ws.add(jsonEncode({'t': 'welcome', 'code': code, 'room': _roomMap()}));
    _emit();
    return uid;
  }

  void _handleCas(WebSocket ws, Map<String, dynamic> m) {
    final id = m['id'];
    final base = (m['base'] as num?)?.toInt();
    final next = (m['ver'] as num?)?.toInt();
    final st = m['state'];
    if (base == version && next != null && st is String) {
      version = next;
      stateJson = st;
      status = m['over'] == true ? 'finished' : 'playing';
      _emit();
      ws.add(jsonEncode({'t': 'casres', 'id': id, 'ok': true}));
    } else {
      ws.add(jsonEncode({'t': 'casres', 'id': id, 'ok': false, 'room': _roomMap()}));
    }
  }

  /// Quick chat: checks a message and passes it on to every device, the host
  /// included. Chat only exists while a game is running, and a player cannot
  /// flood the room (messages closer together than [QuickChatConfig.minRelayGap]
  /// are dropped).
  void _relayChat(String uid, Object? item, Object? n) {
    if (status != 'playing' && status != 'finished') return;
    if (item is! String || item.isEmpty || item.length > QuickChatConfig.maxIdLength) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastChatMs[uid];
    if (last != null && now - last < QuickChatConfig.minRelayGap.inMilliseconds) return;
    _lastChatMs[uid] = now;
    final nonce = n is num ? n.toInt() : now;
    if (!_chat.isClosed) {
      _chat.add(QuickChatEvent(uid: uid, itemId: item, nonce: nonce));
    }
    _sendAll({'t': 'chat', 'uid': uid, 'item': item, 'n': nonce});
  }

  @override
  Stream<QuickChatEvent> get chatStream => _chat.stream;

  @override
  Future<void> sendChat(String itemId) async =>
      _relayChat(hostUid, itemId, DateTime.now().millisecondsSinceEpoch);

  void _onDisconnect(String uid) {
    clients.remove(uid);
    if (status == 'lobby') {
      members.removeWhere((m) => m.uid == uid);
      _emit();
    }
    _maybeShutDown();
  }

  /// A guest leaves the lobby (seat == null) or a running game.
  void _removeGuest(String uid, int? seat) {
    _removePlayer(uid, seat);
    final ws = clients.remove(uid);
    try {
      ws?.close();
    } catch (_) {}
    _maybeShutDown();
  }

  /// Takes a player out: in a running game their seat is vacated (tokens
  /// vanish, the seat is skipped); in the lobby their seat is freed.
  void _removePlayer(String uid, int? seat) {
    if (status == 'playing' && stateJson != null && seat != null) {
      try {
        final g = GameState.fromJson(Map<String, dynamic>.from(jsonDecode(stateJson!) as Map));
        if (seat >= 0 &&
            seat < g.config.playerCount &&
            g.config.seats[seat].uid == uid &&
            g.isActive(seat)) {
          final next = LudoEngine.removeSeat(g, seat, SeatPresence.left);
          // Bots do not keep a room alive: it closes with the last human.
          final anyone = List<int>.generate(next.config.playerCount, (i) => i)
              .any((i) => next.isActive(i) && !next.config.seats[i].isBot);
          version += 1;
          stateJson = jsonEncode(next.toJson());
          status = !anyone
              ? 'closed'
              : (next.phase == LudoPhase.gameOver ? 'finished' : 'playing');
        }
      } catch (_) {}
    }
    if (status == 'lobby') members.removeWhere((m) => m.uid == uid);
    _emit();
  }

  void _maybeShutDown() {
    if (status == 'closed' || (_hostGone && clients.isEmpty)) {
      Future<void>.delayed(const Duration(seconds: 1), shutdown);
    }
  }

  // ------------------------------------------------------------- host actions

  void addBot(String name, BotLevel level) {
    if (status != 'lobby') throw RoomException('The game has already started');
    if (members.length >= criteria.playerCount) throw RoomException('The room is full');
    members.add(RoomMember('bot_${_randomId(8)}', name, DateTime.now(),
        isBot: true, level: level));
    _emit();
  }

  Future<void> removeMember(String id) async {
    if (id == hostUid) throw RoomException('The host cannot remove themselves');
    if (status != 'lobby') throw RoomException('The game has already started');
    final before = members.length;
    members.removeWhere((m) => m.uid == id);
    if (members.length == before) return;
    _emit(); // the removed player sees their seat vanish
    final ws = clients.remove(id);
    try {
      await ws?.close();
    } catch (_) {}
  }

  void startGame(GameState initial) {
    members.removeWhere((m) => m.isBot); // bots live in the game state from now on
    status = 'playing';
    stateJson = jsonEncode(initial.toJson());
    version = 1;
    _emit();
  }

  @override
  Future<bool> publishState(GameState state, int baseVersion, int newVersion) async {
    if (version != baseVersion) return false;
    version = newVersion;
    stateJson = jsonEncode(state.toJson());
    status = state.phase == LudoPhase.gameOver ? 'finished' : 'playing';
    _emit();
    return true;
  }

  /// The host leaves a running game. The room keeps serving the other players
  /// (their game goes on without the host's seat) until the last one is gone.
  @override
  Future<void> leaveGame(int? seat) async {
    _hostGone = true;
    _removePlayer(hostUid, seat);
    members.removeWhere((m) => m.uid == hostUid);
    _maybeShutDown();
    if (clients.isEmpty) await shutdown();
  }

  @override
  Future<void> leaveLobby() => closeRoom();

  Future<void> closeRoom() async {
    status = 'closed';
    _emit();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await shutdown();
  }

  Future<void> shutdown() async {
    if (isShutDown) return;
    isShutDown = true;
    _announce?.cancel();
    _udp?.close();
    for (final ws in clients.values.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    clients.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    if (!_chat.isClosed) await _chat.close();
  }
}

// ------------------------------------------------------------------ guest side

class _ClientSession implements _Session {
  _ClientSession(this.ip, this.port, this.uid);

  final String ip;
  final int port;
  final String uid;

  String _code = '';
  @override
  String get code => _code;
  String get address => '$ip:$port';

  WebSocket? _ws;
  bool _closed = false;
  Map<String, dynamic>? _lastRoomMap;
  Completer<RoomData>? _joining;
  final Map<String, Completer<bool>> _pending = {};
  int _seq = 0;

  final _Replay<RoomData> _room = _Replay<RoomData>();
  final _Replay<List<RoomMember>> _members = _Replay<List<RoomMember>>();
  final StreamController<QuickChatEvent> _chat = StreamController<QuickChatEvent>.broadcast();

  @override
  Stream<RoomData> get roomStream => _room.stream;
  @override
  Stream<List<RoomMember>> get membersStream => _members.stream;
  @override
  RoomData? get currentRoom => _room.last;
  @override
  Stream<QuickChatEvent> get chatStream => _chat.stream;

  Future<RoomData> connect(String name) async {
    final ws = await WebSocket.connect('ws://$ip:$port/ws').timeout(const Duration(seconds: 6));
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 5);
    final joining = _joining = Completer<RoomData>();
    ws.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed());
    ws.add(jsonEncode({'t': 'join', 'uid': uid, 'name': name}));
    return joining.future.timeout(const Duration(seconds: 6),
        onTimeout: () => throw RoomException('The host did not answer'));
  }

  void _publishRoom(Map<String, dynamic> room, Object? members) {
    _lastRoomMap = room;
    _room.add(RoomData.fromMap(_code, room));
    if (members != null) _members.add(_membersFromJson(members));
  }

  void _onData(dynamic data) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'welcome':
        _code = m['code'] as String? ?? '';
        final room = Map<String, dynamic>.from(m['room'] as Map);
        final j = _joining;
        _joining = null;
        j?.complete(RoomData.fromMap(_code, room));
      case 'error':
        final j = _joining;
        _joining = null;
        j?.completeError(RoomException(m['message'] as String? ?? 'Could not join'));
      case 'room':
        _publishRoom(Map<String, dynamic>.from(m['room'] as Map), m['members']);
      case 'casres':
        final c = _pending.remove(m['id']);
        if (m['ok'] != true && m['room'] is Map) {
          _publishRoom(Map<String, dynamic>.from(m['room'] as Map), null);
        }
        c?.complete(m['ok'] == true);
      case 'chat':
        final cu = m['uid'];
        final ci = m['item'];
        final cn = m['n'];
        if (cu is String && ci is String && cn is num && !_chat.isClosed) {
          _chat.add(QuickChatEvent(uid: cu, itemId: ci, nonce: cn.toInt()));
        }
    }
  }

  /// Socket gone: the host left, crashed or went out of range.
  void _onClosed() {
    if (_closed) return;
    _closed = true;
    final j = _joining;
    _joining = null;
    if (j != null && !j.isCompleted) {
      j.completeError(RoomException('Could not reach the host'));
    }
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _pending.clear();
    final last = _lastRoomMap;
    if (last != null && last['status'] != 'closed') {
      _room.add(RoomData.fromMap(_code, {...last, 'status': 'closed'}));
    }
  }

  @override
  Future<bool> publishState(GameState state, int baseVersion, int newVersion) async {
    final ws = _ws;
    if (ws == null || _closed) return false;
    final id = '${++_seq}';
    final c = Completer<bool>();
    _pending[id] = c;
    ws.add(jsonEncode({
      't': 'cas',
      'id': id,
      'base': baseVersion,
      'ver': newVersion,
      'over': state.phase == LudoPhase.gameOver,
      'state': jsonEncode(state.toJson()),
    }));
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _pending.remove(id);
      return false;
    });
  }

  @override
  Future<void> sendChat(String itemId) async {
    final ws = _ws;
    if (ws == null || _closed) throw RoomException('The connection to the host was lost');
    ws.add(jsonEncode({
      't': 'chat',
      'item': itemId,
      'n': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  @override
  Future<void> leaveGame(int? seat) async {
    try {
      _ws?.add(jsonEncode({'t': 'leaveGame', 'seat': seat}));
    } catch (_) {}
    await close();
  }

  @override
  Future<void> leaveLobby() async {
    try {
      _ws?.add(jsonEncode({'t': 'leave'}));
    } catch (_) {}
    await close();
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _ws?.close();
    } catch (_) {}
    if (!_chat.isClosed) await _chat.close();
  }
}

// ------------------------------------------------------------------- discovery

/// A room announced by a host on the local network.
class LanRoomInfo {
  final String code;
  final String hostName;
  final String ip;
  final int port;
  final RoomData room;
  final DateTime lastSeen;

  const LanRoomInfo({
    required this.code,
    required this.hostName,
    required this.ip,
    required this.port,
    required this.room,
    required this.lastSeen,
  });

  String get address => '$ip:$port';
  int get players => room.memberCount;
  int get capacity => room.playerCount;
  bool get isFull => players >= capacity;
}

/// Listens for the UDP announcements hosts send while their room is open.
class LanDiscovery {
  static const port = 45678;
  static const appId = 'ludo-lan-1';
  static const _expiry = Duration(seconds: 4);

  /// Emits the current list of rooms whenever it changes (a room that stops
  /// announcing disappears after a few seconds).
  Stream<List<LanRoomInfo>> scan() {
    final rooms = <String, LanRoomInfo>{};
    RawDatagramSocket? socket;
    Timer? prune;
    late final StreamController<List<LanRoomInfo>> ctl;

    void push() {
      if (ctl.isClosed) return;
      final list = rooms.values.toList()
        ..sort((a, b) => a.hostName.toLowerCase().compareTo(b.hostName.toLowerCase()));
      ctl.add(list);
    }

    ctl = StreamController<List<LanRoomInfo>>(
      onListen: () async {
        try {
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
              reuseAddress: true);
          socket!.broadcastEnabled = true;
          socket!.listen((event) {
            if (event != RawSocketEvent.read) return;
            final d = socket?.receive();
            if (d == null) return;
            try {
              final m = Map<String, dynamic>.from(
                  jsonDecode(utf8.decode(d.data)) as Map);
              if (m['app'] != appId) return;
              final code = m['code'] as String;
              final p = (m['port'] as num).toInt();
              final ip = d.address.address;
              rooms['$ip:$p'] = LanRoomInfo(
                code: code,
                hostName: m['host'] as String? ?? 'Host',
                ip: ip,
                port: p,
                room: RoomData.fromMap(code, Map<String, dynamic>.from(m['room'] as Map)),
                lastSeen: DateTime.now(),
              );
              push();
            } catch (_) {}
          });
        } catch (e) {
          if (!ctl.isClosed) ctl.addError(e);
        }
        prune = Timer.periodic(const Duration(seconds: 1), (_) {
          final cutoff = DateTime.now().subtract(_expiry);
          final before = rooms.length;
          rooms.removeWhere((_, r) => r.lastSeen.isBefore(cutoff));
          if (rooms.length != before) push();
        });
      },
      onCancel: () {
        prune?.cancel();
        socket?.close();
      },
    );
    return ctl.stream;
  }
}
