import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/quick_chat_catalog.dart';
import '../data/online_repository.dart' show RoomBackend;
import '../data/quick_chat_event.dart';

/// The bubbles currently on the board, one per seat at most.
final quickChatProvider =
    NotifierProvider<QuickChatController, QuickChatState>(QuickChatController.new);

/// A message bubble shown at a seat's yard.
class ChatBubble {
  const ChatBubble({required this.itemId, required this.seq});

  /// `QuickChatItem.id` of the message.
  final String itemId;

  /// Unique per bubble shown on this device. A replacement bubble gets a new
  /// [seq], so the widget (keyed by it) starts its pop-in animation again.
  final int seq;
}

class QuickChatState {
  const QuickChatState([this.bubbles = const {}]);

  /// Seat index -> the bubble that seat is currently showing.
  final Map<int, ChatBubble> bubbles;
}

/// Sends quick chat messages and turns incoming ones into board bubbles.
///
/// Used by online and Wi-Fi games only. [LudoController] calls [attach] when
/// such a game starts and [detach] when it ends; local and AI games never
/// attach, so they have no chat.
class QuickChatController extends Notifier<QuickChatState> {
  RoomBackend? _backend;
  String? _code;
  int? Function(String uid)? _seatOf;
  StreamSubscription<QuickChatEvent>? _sub;

  final Map<int, Timer> _timers = {};
  final Map<String, int> _lastNonce = {};
  int _seq = 0;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  QuickChatState build() {
    ref.onDispose(_stop);
    return const QuickChatState();
  }

  /// Starts listening to [backend]'s chat for room [code]. [seatOf] maps a
  /// sender's uid to its seat (null if that player is not in the game).
  void attach({
    required RoomBackend backend,
    required String code,
    required int? Function(String uid) seatOf,
  }) {
    detach();
    _backend = backend;
    _code = code;
    _seatOf = seatOf;
    _sub = backend.watchQuickChat(code).listen(_onEvent, onError: (_) {});
  }

  /// Stops listening and clears every bubble.
  void detach() {
    _stop();
    if (state.bubbles.isNotEmpty) state = const QuickChatState();
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _backend = null;
    _code = null;
    _seatOf = null;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _lastNonce.clear();
  }

  /// Whether a game with chat is running on this device.
  bool get isAttached => _backend != null;

  /// Sends [itemId] to the other players. Returns false when nothing was sent:
  /// no chat game, an unknown id, or the sender is still in the short cooldown
  /// after their previous message.
  ///
  /// The bubble is not drawn here: it comes back through the backend like every
  /// other player's, so what the sender sees is what everyone sees. Failures are
  /// swallowed; chat is never worth interrupting a game for.
  bool send(String itemId) {
    final backend = _backend;
    final code = _code;
    if (backend == null || code == null) return false;
    if (QuickChatCatalog.byId(itemId) == null) return false;
    final now = DateTime.now();
    if (now.difference(_lastSent) < QuickChatConfig.sendCooldown) return false;
    _lastSent = now;
    unawaited(backend.sendQuickChat(code, itemId).catchError((Object _) {}));
    return true;
  }

  void _onEvent(QuickChatEvent e) {
    if (QuickChatCatalog.byId(e.itemId) == null) return; // newer app, unknown item
    if (_lastNonce[e.uid] == e.nonce) return; // the same message, reported twice
    _lastNonce[e.uid] = e.nonce;
    final seat = _seatOf?.call(e.uid);
    if (seat == null) return;

    // A new message replaces the old bubble of that seat and restarts the clock.
    _timers.remove(seat)?.cancel();
    final bubble = ChatBubble(itemId: e.itemId, seq: ++_seq);
    state = QuickChatState({...state.bubbles, seat: bubble});
    _timers[seat] = Timer(QuickChatConfig.bubbleDuration, () {
      _timers.remove(seat);
      if (state.bubbles[seat]?.seq != bubble.seq) return;
      state = QuickChatState({...state.bubbles}..remove(seat));
    });
  }
}
