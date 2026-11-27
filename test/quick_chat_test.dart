import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo/features/ludo/chat/quick_chat_catalog.dart';
import 'package:ludo/features/ludo/data/online_repository.dart' show RoomBackend;
import 'package:ludo/features/ludo/data/quick_chat_event.dart';
import 'package:ludo/features/ludo/state/quick_chat_controller.dart';

/// Only the two chat methods are real; the rest of [RoomBackend] is not used.
class _FakeBackend implements RoomBackend {
  final StreamController<QuickChatEvent> events = StreamController<QuickChatEvent>.broadcast();
  final List<String> sent = [];

  @override
  Future<void> sendQuickChat(String code, String itemId) async => sent.add(itemId);

  @override
  Stream<QuickChatEvent> watchQuickChat(String code) => events.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int? _seatOf(String uid) => const {'u1': 0, 'u2': 1}[uid];

QuickChatEvent _ev(String uid, String item, int n) =>
    QuickChatEvent(uid: uid, itemId: item, nonce: n);

void main() {
  group('QuickChatCatalog', () {
    test('ids are unique, short and every item has something to show', () {
      final ids = <String>{};
      for (final i in QuickChatCatalog.items) {
        expect(ids.add(i.id), isTrue, reason: 'duplicate id ${i.id}');
        expect(i.id, isNotEmpty);
        expect(i.id.length, lessThanOrEqualTo(QuickChatConfig.maxIdLength));
        expect(i.text != null || i.emoji != null, isTrue, reason: i.id);
      }
    });

    test('has the starter messages and reactions', () {
      for (final id in ['nice', 'oops', 'gg', 'laugh', 'thumbs_up']) {
        expect(QuickChatCatalog.byId(id), isNotNull, reason: id);
      }
      expect(QuickChatCatalog.byId('nice')!.text, 'Nice!');
      expect(QuickChatCatalog.byId('laugh')!.emoji, '😂');
      expect(QuickChatCatalog.byId('no_such_item'), isNull);
    });

    test('every category has items', () {
      for (final c in QuickChatCategory.values) {
        expect(QuickChatCatalog.inCategory(c), isNotEmpty, reason: c.name);
      }
    });
  });

  group('QuickChatController', () {
    testWidgets('shows a bubble at the sender seat, then removes it', (tester) async {
      final container = ProviderContainer();
      final backend = _FakeBackend();
      container.read(quickChatProvider.notifier).attach(backend: backend, code: 'ABC', seatOf: _seatOf);

      backend.events.add(_ev('u1', 'nice', 1));
      await tester.pump();
      expect(container.read(quickChatProvider).bubbles.keys, [0]);
      expect(container.read(quickChatProvider).bubbles[0]!.itemId, 'nice');

      await tester.pump(QuickChatConfig.bubbleDuration + const Duration(milliseconds: 100));
      expect(container.read(quickChatProvider).bubbles, isEmpty);
      container.dispose();
    });

    testWidgets('a new message replaces the old bubble and restarts the timer', (tester) async {
      final container = ProviderContainer();
      final backend = _FakeBackend();
      container.read(quickChatProvider.notifier).attach(backend: backend, code: 'ABC', seatOf: _seatOf);

      backend.events.add(_ev('u1', 'nice', 1));
      await tester.pump();
      final firstSeq = container.read(quickChatProvider).bubbles[0]!.seq;

      await tester.pump(const Duration(seconds: 3));
      backend.events.add(_ev('u1', 'oops', 2));
      await tester.pump();
      final b = container.read(quickChatProvider).bubbles[0]!;
      expect(b.itemId, 'oops');
      expect(b.seq, isNot(firstSeq));
      expect(container.read(quickChatProvider).bubbles.length, 1);

      // 6 s after the first message: the first bubble's timer would have fired
      // long ago, so the replacement being alive shows that timer was cancelled.
      await tester.pump(const Duration(seconds: 3));
      expect(container.read(quickChatProvider).bubbles[0]?.itemId, 'oops');

      await tester.pump(const Duration(seconds: 2));
      expect(container.read(quickChatProvider).bubbles, isEmpty);
      container.dispose();
    });

    testWidgets('seats are independent', (tester) async {
      final container = ProviderContainer();
      final backend = _FakeBackend();
      container.read(quickChatProvider.notifier).attach(backend: backend, code: 'ABC', seatOf: _seatOf);

      backend.events.add(_ev('u1', 'nice', 1));
      backend.events.add(_ev('u2', 'laugh', 1));
      await tester.pump();
      final bubbles = container.read(quickChatProvider).bubbles;
      expect(bubbles[0]!.itemId, 'nice');
      expect(bubbles[1]!.itemId, 'laugh');

      await tester.pump(QuickChatConfig.bubbleDuration + const Duration(milliseconds: 100));
      container.dispose();
    });

    testWidgets('ignores repeats, unknown items and players who are not seated', (tester) async {
      final container = ProviderContainer();
      final backend = _FakeBackend();
      container.read(quickChatProvider.notifier).attach(backend: backend, code: 'ABC', seatOf: _seatOf);

      backend.events.add(_ev('u1', 'nice', 7));
      await tester.pump();
      final seq = container.read(quickChatProvider).bubbles[0]!.seq;

      backend.events.add(_ev('u1', 'nice', 7)); // same message reported twice
      backend.events.add(_ev('u2', 'from_a_newer_app', 1)); // unknown item
      backend.events.add(_ev('stranger', 'nice', 1)); // not in the game
      await tester.pump();
      final bubbles = container.read(quickChatProvider).bubbles;
      expect(bubbles.keys, [0]);
      expect(bubbles[0]!.seq, seq);

      await tester.pump(QuickChatConfig.bubbleDuration + const Duration(milliseconds: 100));
      container.dispose();
    });

    testWidgets('send checks the id, the cooldown and the attachment', (tester) async {
      final container = ProviderContainer();
      final backend = _FakeBackend();
      final ctrl = container.read(quickChatProvider.notifier);

      expect(ctrl.send('nice'), isFalse); // no chat game running

      ctrl.attach(backend: backend, code: 'ABC', seatOf: _seatOf);
      expect(ctrl.send('not_in_catalogue'), isFalse);
      expect(ctrl.send('nice'), isTrue);
      expect(ctrl.send('oops'), isFalse); // cooldown
      expect(backend.sent, ['nice']);

      ctrl.detach();
      expect(ctrl.send('nice'), isFalse);
      container.dispose();
    });

    testWidgets('detach clears bubbles and stops listening', (tester) async {
      final container = ProviderContainer();
      final backend = _FakeBackend();
      final ctrl = container.read(quickChatProvider.notifier);
      ctrl.attach(backend: backend, code: 'ABC', seatOf: _seatOf);

      backend.events.add(_ev('u1', 'nice', 1));
      await tester.pump();
      expect(container.read(quickChatProvider).bubbles, isNotEmpty);

      ctrl.detach();
      expect(container.read(quickChatProvider).bubbles, isEmpty);

      backend.events.add(_ev('u1', 'oops', 2));
      await tester.pump();
      expect(container.read(quickChatProvider).bubbles, isEmpty);
      container.dispose();
    });
  });
}
