import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../engine/engine.dart';
import 'quick_chat_event.dart';

enum IntentType { roll, move }

class RoomData {
  final String code;
  final String hostUid;
  final String status; // lobby | playing | finished | closed
  final int playerCount;
  final int teamPreset; // -1 = no teams
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
  final int turnSeconds; // 0 = no limit
  final int version;
  final String? stateJson;

  /// Seats taken in the lobby (kept in step with the members sub-collection).
  final int memberCount;

  /// Quick Start rooms are public and carry a [matchKey]; private rooms don't.
  final bool isPublic;
  final String? matchKey;
  final DateTime? createdAt;

  /// Last heartbeat of the host (Quick Start lobbies only).
  final DateTime? hostPing;

  const RoomData({
    required this.code,
    required this.hostUid,
    required this.status,
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
    this.threeSixesForfeit = false,
    this.bounceBack = false,
    this.turnSeconds = 30,
    required this.version,
    required this.stateJson,
    required this.memberCount,
    required this.isPublic,
    required this.matchKey,
    required this.createdAt,
    required this.hostPing,
  });

  factory RoomData.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) =>
      RoomData.fromMap(d.id, d.data() ?? const <String, dynamic>{});

  factory RoomData.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    return RoomData(
      code: id,
      hostUid: m['hostUid'] as String? ?? '',
      status: m['status'] as String? ?? 'lobby',
      playerCount: (m['playerCount'] as num?)?.toInt() ?? 4,
      teamPreset: (m['teamPreset'] as num?)?.toInt() ?? -1,
      bonusOnCapture: m['bonusOnCapture'] as bool? ?? false,
      bonusOnFinish: m['bonusOnFinish'] as bool? ?? false,
      bonusOnOne: m['bonusOnOne'] as bool? ?? false,
      enterOnOne: m['enterOnOne'] as bool? ?? false,
      rankAll: m['rankAll'] as bool? ?? true,
      tokenCount: ((m['tokenCount'] as num?)?.toInt() ?? 4).clamp(1, 4),
      oneTokenOut: m['oneTokenOut'] as bool? ?? false,
      stackedCapture: m['stackedCapture'] as bool? ?? true,
      threeSixesForfeit: m['threeSixesForfeit'] as bool? ?? false,
      bounceBack: m['bounceBack'] as bool? ?? false,
      turnSeconds: (m['turnSeconds'] as num?)?.toInt() ?? 30,
      version: (m['version'] as num?)?.toInt() ?? 0,
      stateJson: m['state'] as String?,
      memberCount: (m['memberCount'] as num?)?.toInt() ?? 0,
      isPublic: m['public'] as bool? ?? false,
      matchKey: m['matchKey'] as String?,
      createdAt: ts(m['createdAt']),
      hostPing: ts(m['hostPing']),
    );
  }

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

  /// A host that has not pinged for this long is treated as gone.
  static const staleAfter = Duration(seconds: 150);

  bool isHostAlive(DateTime now) =>
      hostPing == null || now.difference(hostPing!) < staleAfter;

  /// Oldest room first; ties broken by code so every client agrees.
  static int oldestFirst(RoomData a, RoomData b) {
    final now = DateTime.now();
    final c = (a.createdAt ?? now).compareTo(b.createdAt ?? now);
    return c != 0 ? c : a.code.compareTo(b.code);
  }
}

class RoomMember {
  final String uid;
  final String name;
  final DateTime joinedAt;

  /// Lobby-only placeholder added by the host to fill an open seat.
  final bool isBot;
  final BotLevel level;
  const RoomMember(this.uid, this.name, this.joinedAt,
      {this.isBot = false, this.level = BotLevel.medium});
}

class RoomIntent {
  final String id;
  final String uid;
  final IntentType type;
  final int seat;
  final int? tokenSeat;
  final int? tokenIndex;
  const RoomIntent({
    required this.id,
    required this.uid,
    required this.type,
    required this.seat,
    this.tokenSeat,
    this.tokenIndex,
  });

  factory RoomIntent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return RoomIntent(
      id: d.id,
      uid: m['uid'] as String? ?? '',
      type: m['type'] == 'move' ? IntentType.move : IntentType.roll,
      seat: (m['seat'] as num?)?.toInt() ?? -1,
      tokenSeat: (m['tokenSeat'] as num?)?.toInt(),
      tokenIndex: (m['tokenIndex'] as num?)?.toInt(),
    );
  }
}

/// What the lobby screen and the game controller need from a room service.
/// Implemented by the Firestore repository (online play) and by the
/// local-network backend (hotspot / Wi-Fi play).
abstract class RoomBackend {
  Future<String> signIn();
  Future<String> createRoom({
    required String hostName,
    required MatchCriteria criteria,
    bool quick = false,
  });
  Future<RoomData> joinRoom(String code, String name, {String? requireMatchKey});
  Stream<RoomData> watchRoom(String code);
  Stream<List<RoomMember>> watchMembers(String code);
  Future<RoomData?> getRoom(String code);
  Future<void> startGame(String code, GameState initial, {List<String> botIds = const []});
  Future<void> addBot(String code, String name, BotLevel level);
  Future<void> removeMember(String code, String memberId);
  Future<bool> publishStateCas(String code, GameState state, int baseVersion, int newVersion);
  Future<void> leaveGame(String code, int? seat);
  Future<void> leaveRoom(String code);
  Future<void> closeRoom(String code);

  /// Quick chat. Messages are tiny and independent of the game state: they are
  /// never versioned, so sending one can never conflict with a move.
  ///
  /// Every player in the room, the sender included, receives the event from
  /// [watchQuickChat] (the Firestore SDK echoes local writes at once; the Wi-Fi
  /// host relays to everybody).
  Future<void> sendQuickChat(String code, String itemId);
  Stream<QuickChatEvent> watchQuickChat(String code);
}

class RoomException implements Exception {
  final String message;
  RoomException(this.message);
  @override
  String toString() => message;
}

class _CodeTaken implements Exception {}

/// Firestore access for online games.
///
/// Architecture: the host's device is the authority. Guests never edit the
/// game state; they write small "intents" (roll / move token) which the host
/// validates with [LudoEngine], applies, and publishes as the new room state.
/// See firestore.rules for the matching security rules.
///
/// Two ways to get a room:
///  * Create Room - private room, shared by its 6-character code.
///  * Quick Start - a public room tagged with a [MatchCriteria.key]; players are
///    only ever put together when that key is identical.
class LudoOnlineRepository implements RoomBackend {
  /// True once Firebase.initializeApp() has succeeded.
  static bool get isAvailable {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  CollectionReference<Map<String, dynamic>> get _rooms => _db.collection('ludo_rooms');

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _randomCode() {
    final r = math.Random.secure();
    return List.generate(6, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
  }

  @override
  Future<String> signIn() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
    if (user == null) throw RoomException('Could not sign in to Firebase');
    return user.uid;
  }

  /// Creates a room and seats the host in it (one atomic write).
  /// With [quick] the room is public and tagged for matchmaking.
  @override
  Future<String> createRoom({
    required String hostName,
    required MatchCriteria criteria,
    bool quick = false,
  }) async {
    final uid = await signIn();
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = _randomCode();
      final ref = _rooms.doc(code);
      try {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (snap.exists) throw _CodeTaken();
          tx.set(ref, {
            'hostUid': uid,
            'status': 'lobby',
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
            'version': 0,
            'memberCount': 1,
            'public': quick,
            if (quick) 'matchKey': criteria.key,
            'createdAt': FieldValue.serverTimestamp(),
            'hostPing': FieldValue.serverTimestamp(),
          });
          tx.set(ref.collection('members').doc(uid), {
            'name': hostName,
            'joinedAt': FieldValue.serverTimestamp(),
          });
        });
        return code;
      } on _CodeTaken {
        continue;
      }
    }
    throw RoomException('Could not allocate a room code, please try again');
  }

  /// Takes a seat in a lobby. The seat count is checked and incremented inside
  /// a transaction, so two players can never take the last seat together.
  /// [requireMatchKey] makes the join fail unless the room still has exactly
  /// that matchmaking key.
  @override
  Future<RoomData> joinRoom(String rawCode, String name, {String? requireMatchKey}) async {
    final uid = await signIn();
    final code = rawCode.trim().toUpperCase();
    final ref = _rooms.doc(code);
    final memberRef = ref.collection('members').doc(uid);
    RoomData? joined;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw RoomException('Room $code was not found');
      final room = RoomData.fromDoc(snap);
      if (room.status != 'lobby') throw RoomException('That game has already started');
      if (requireMatchKey != null && room.matchKey != requireMatchKey) {
        throw RoomException('That room uses different settings');
      }
      final mine = await tx.get(memberRef);
      if (mine.exists) {
        tx.update(memberRef, {'name': name});
      } else {
        if (room.memberCount >= room.playerCount) throw RoomException('The room is full');
        tx.update(ref, {'memberCount': room.memberCount + 1});
        tx.set(memberRef, {'name': name, 'joinedAt': FieldValue.serverTimestamp()});
      }
      joined = room;
    });
    return joined!;
  }

  // -------------------------------------------------------------- quick start

  /// Open public lobbies whose key is exactly [criteria]'s key, oldest first.
  /// Every condition is re-checked on the client so a room only qualifies when
  /// player count and all rules are identical.
  Future<List<RoomData>> findQuickRooms(MatchCriteria criteria, {String? excludeCode}) async {
    final uid = await signIn();
    final key = criteria.key;
    final snap = await _rooms
        .where('matchKey', isEqualTo: key)
        .where('status', isEqualTo: 'lobby')
        .limit(30)
        .get();
    final now = DateTime.now();
    final list = snap.docs
        .map(RoomData.fromDoc)
        .where((r) =>
            r.isPublic &&
            r.matchKey == key &&
            r.criteria == criteria &&
            r.status == 'lobby' &&
            r.hostUid != uid &&
            r.code != excludeCode &&
            r.memberCount < r.playerCount &&
            r.isHostAlive(now))
        .toList()
      ..sort(RoomData.oldestFirst);
    return list;
  }

  /// Joins the oldest matching open lobby, or returns null if there is none.
  Future<RoomData?> quickJoin(MatchCriteria criteria, String name) async {
    for (final r in await findQuickRooms(criteria)) {
      try {
        return await joinRoom(r.code, name, requireMatchKey: criteria.key);
      } on RoomException {
        continue; // filled up or closed in the meantime: try the next one
      }
    }
    return null;
  }

  /// Another matching lobby that is older than [mine]. Two searchers who both
  /// created a room at the same moment use this to merge into one.
  Future<RoomData?> findOlderQuickRoom(RoomData mine) async {
    final list = await findQuickRooms(mine.criteria, excludeCode: mine.code);
    for (final r in list) {
      if (RoomData.oldestFirst(r, mine) < 0) return r;
    }
    return null;
  }

  /// Host heartbeat so abandoned Quick Start lobbies stop being offered.
  Future<void> pingRoom(String code) async {
    try {
      await _rooms.doc(code).update({'hostPing': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // ------------------------------------------------------------------- rooms

  @override
  Stream<RoomData> watchRoom(String code) => _rooms
      .doc(code)
      .snapshots()
      .where((s) => s.exists)
      .map(RoomData.fromDoc);

  @override
  Stream<List<RoomMember>> watchMembers(String code) =>
      _rooms.doc(code).collection('members').snapshots().map((q) {
        final list = q.docs.map((d) {
          final m = d.data();
          final ts = m['joinedAt'];
          final lv = (m['level'] as num?)?.toInt() ?? BotLevel.medium.index;
          return RoomMember(
            d.id,
            m['name'] as String? ?? 'Player',
            ts is Timestamp ? ts.toDate() : DateTime.now(),
            isBot: d.id.startsWith('bot_') && m['bot'] == true,
            level: BotLevel.values[lv.clamp(0, BotLevel.values.length - 1)],
          );
        }).toList()
          ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        return list;
      });

  /// Host only: flips the room to "playing" and publishes the first state.
  /// The lobby's bot placeholders ([botIds]) are removed in the same write;
  /// from now on the bots live only inside the game state.
  @override
  Future<void> startGame(String code, GameState initial, {List<String> botIds = const []}) {
    final ref = _rooms.doc(code);
    final batch = _db.batch();
    batch.update(ref, {
      'status': 'playing',
      'state': jsonEncode(initial.toJson()),
      'version': 1,
    });
    for (final id in botIds) {
      batch.delete(ref.collection('members').doc(id));
    }
    return batch.commit();
  }

  /// Host only: puts a bot into an open seat of a private lobby.
  @override
  Future<void> addBot(String code, String name, BotLevel level) async {
    final uid = await signIn();
    final ref = _rooms.doc(code);
    final r = math.Random.secure();
    final id = 'bot_${List.generate(8, (_) => _alphabet[r.nextInt(_alphabet.length)]).join()}';
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw RoomException('The room no longer exists');
      final room = RoomData.fromDoc(snap);
      if (room.hostUid != uid) throw RoomException('Only the host can add bots');
      if (room.status != 'lobby') throw RoomException('The game has already started');
      if (room.memberCount >= room.playerCount) throw RoomException('The room is full');
      tx.update(ref, {'memberCount': room.memberCount + 1});
      tx.set(ref.collection('members').doc(id), {
        'name': name,
        'bot': true,
        'level': level.index,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Host only: removes a bot or kicks a joined player out of the lobby.
  /// The removed player's device notices that its member record is gone.
  @override
  Future<void> removeMember(String code, String memberId) async {
    final uid = await signIn();
    final ref = _rooms.doc(code);
    final memberRef = ref.collection('members').doc(memberId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      if (data['hostUid'] != uid) throw RoomException('Only the host can remove players');
      if (memberId == uid) throw RoomException('The host cannot remove themselves');
      if (data['status'] != 'lobby') throw RoomException('The game has already started');
      final m = await tx.get(memberRef);
      if (!m.exists) return;
      tx.delete(memberRef);
      final c = (data['memberCount'] as num?)?.toInt() ?? 1;
      if (c > 0) tx.update(ref, {'memberCount': c - 1});
    });
  }

  /// Host only: publishes a new authoritative state.
  Future<void> publishState(String code, GameState state, int version) =>
      _rooms.doc(code).update({
        'state': jsonEncode(state.toJson()),
        'version': version,
        'status': state.phase == LudoPhase.gameOver ? 'finished' : 'playing',
      });

  /// Host only: closes the room. Once nobody else is in it the room and its
  /// sub-collections are deleted; guests that are still inside get a few
  /// seconds to notice the closure, then the host removes everything anyway.
  @override
  Future<void> closeRoom(String code) async {
    await _rooms.doc(code).update({'status': 'closed'});
    try {
      final uid = _auth.currentUser?.uid;
      final members = await _rooms.doc(code).collection('members').get();
      final others = members.docs.where((d) => d.id != uid);
      if (others.isEmpty) {
        await deleteRoom(code);
      } else {
        Future<void>.delayed(const Duration(seconds: 5), () => deleteRoom(code));
      }
    } catch (_) {}
  }

  /// Deletes the room document together with its members, intents and chat
  /// (Firestore does not delete sub-collections on its own). Best effort:
  /// failures are ignored, e.g. when somebody else already deleted the room.
  Future<void> deleteRoom(String code) async {
    try {
      final ref = _rooms.doc(code);
      final batch = _db.batch();
      final members = await ref.collection('members').get();
      for (final d in members.docs) {
        batch.delete(d.reference);
      }
      final intents = await ref.collection('intents').get();
      for (final d in intents.docs) {
        batch.delete(d.reference);
      }
      final chat = await ref.collection('chat').get();
      for (final d in chat.docs) {
        batch.delete(d.reference);
      }
      batch.delete(ref);
      await batch.commit();
    } catch (_) {}
  }

  /// Called after a player left: when the game is over (or closed) and no
  /// member is left, the last one out deletes the room.
  Future<void> _deleteIfAbandoned(String code) async {
    try {
      final ref = _rooms.doc(code);
      final snap = await ref.get();
      if (!snap.exists) return;
      final status = snap.data()?['status'];
      if (status != 'finished' && status != 'closed') return;
      final members = await ref.collection('members').limit(1).get();
      if (members.docs.isEmpty) await deleteRoom(code);
    } catch (_) {}
  }

  /// Frees this player's seat (and the seat counter while still in the lobby).
  @override
  Future<void> leaveRoom(String code) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = _rooms.doc(code);
    final memberRef = ref.collection('members').doc(uid);
    await _db.runTransaction((tx) async {
      final room = await tx.get(ref);
      final mine = await tx.get(memberRef);
      if (!mine.exists) return;
      tx.delete(memberRef);
      final data = room.data();
      if (room.exists && data != null && data['status'] == 'lobby') {
        final c = (data['memberCount'] as num?)?.toInt() ?? 1;
        if (c > 0) tx.update(ref, {'memberCount': c - 1});
      }
    });
    await _deleteIfAbandoned(code);
  }

  // ------------------------------------------------- peer-to-peer game state

  /// Writes a new game state only if nobody else wrote in the meantime
  /// (the stored version must still be [baseVersion]). Returns false on a
  /// conflict; the caller then re-reads the room with [getRoom].
  @override
  Future<bool> publishStateCas(
      String code, GameState state, int baseVersion, int newVersion) {
    // A plain update instead of a read-then-write transaction: one round trip
    // instead of two, and on Windows far less work on the UI thread (the
    // Firestore plugin runs there, so a transaction froze the screen at every
    // roll and move). The compare-and-set is done by firestore.rules, which
    // only accept a write whose version is exactly the stored version + 1; a
    // write that lost the race is refused with permission-denied.
    final ref = _rooms.doc(code);
    return ref.update({
      'state': jsonEncode(state.toJson()),
      'version': newVersion,
      'status': state.phase == LudoPhase.gameOver ? 'finished' : 'playing',
    }).then<bool>((_) => true).onError<FirebaseException>((e, _) {
      if (e.code == 'permission-denied') return false; // conflict: caller resyncs
      throw e;
    });
  }

  @override
  Future<RoomData?> getRoom(String code) async {
    final s = await _rooms.doc(code).get();
    return s.exists ? RoomData.fromDoc(s) : null;
  }

  /// A player leaves a running game. Their seat is taken out of the game: the
  /// tokens vanish from the board, the seat is marked as left and skipped, and
  /// the remaining players keep playing (they are told by the state change
  /// itself). Seats are never handed to bots. The game ends when a single team
  /// is left, and the room is closed when nobody is left at all.
  ///
  /// Also used by a player who was already removed for inactivity: then only
  /// their member record is deleted.
  @override
  Future<void> leaveGame(String code, int? seat) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final ref = _rooms.doc(code);
    final memberRef = ref.collection('members').doc(uid);
    await _db.runTransaction((tx) async {
      final room = await tx.get(ref);
      final mine = await tx.get(memberRef);
      final data = room.data();
      if (room.exists && data != null) {
        final status = data['status'];
        final js = data['state'];
        if (status == 'playing' && js is String && seat != null) {
          final g = GameState.fromJson(Map<String, dynamic>.from(jsonDecode(js) as Map));
          if (seat >= 0 &&
              seat < g.config.playerCount &&
              g.config.seats[seat].uid == uid &&
              g.isActive(seat)) {
            final next = LudoEngine.removeSeat(g, seat, SeatPresence.left);
            // Bots do not keep a room alive: it closes with the last human.
            final anyoneLeft = List<int>.generate(next.config.playerCount, (i) => i)
                .any((i) => next.isActive(i) && !next.config.seats[i].isBot);
            final ver = (data['version'] as num?)?.toInt() ?? 0;
            tx.update(ref, {
              'state': jsonEncode(next.toJson()),
              'version': ver + 1,
              'status': !anyoneLeft
                  ? 'closed'
                  : (next.phase == LudoPhase.gameOver ? 'finished' : 'playing'),
            });
          }
        }
      }
      if (mine.exists) tx.delete(memberRef);
    });
    await _deleteIfAbandoned(code);
  }

  // --------------------------------------------------------------- quick chat

  /// One document per player (`chat/{uid}`) that every new message overwrites:
  /// the room never accumulates chat history, and "latest message wins" is
  /// exactly what the board bubbles need.
  @override
  Future<void> sendQuickChat(String code, String itemId) async {
    final uid = await signIn();
    await _rooms.doc(code).collection('chat').doc(uid).set({
      'item': itemId,
      'n': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// New or changed chat documents, as events. The first snapshot only holds
  /// what was said before this listener started, so it is skipped.
  @override
  Stream<QuickChatEvent> watchQuickChat(String code) async* {
    var primed = false;
    await for (final q in _rooms.doc(code).collection('chat').snapshots()) {
      if (!primed) {
        primed = true;
        continue;
      }
      for (final c in q.docChanges) {
        if (c.type == DocumentChangeType.removed) continue;
        final m = c.doc.data();
        final item = m?['item'];
        final n = m?['n'];
        if (item is! String || n is! num) continue;
        yield QuickChatEvent(uid: c.doc.id, itemId: item, nonce: n.toInt());
      }
    }
  }

  // ------------------------------------------------------------------ intents

  Future<void> sendIntent(
    String code,
    IntentType type, {
    required int seat,
    TokenRef? token,
  }) async {
    final uid = await signIn();
    await _rooms.doc(code).collection('intents').add({
      'uid': uid,
      'type': type.name,
      'seat': seat,
      if (token != null) 'tokenSeat': token.seat,
      if (token != null) 'tokenIndex': token.index,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Host only: emits every newly created intent, oldest first.
  Stream<RoomIntent> watchIntents(String code) => _rooms
      .doc(code)
      .collection('intents')
      .orderBy('createdAt')
      .snapshots()
      .expand((q) => q.docChanges
          .where((c) => c.type == DocumentChangeType.added)
          .map((c) => RoomIntent.fromDoc(c.doc as DocumentSnapshot<Map<String, dynamic>>)));

  Future<void> ackIntent(String code, String id) async {
    try {
      await _rooms.doc(code).collection('intents').doc(id).delete();
    } catch (_) {}
  }
}