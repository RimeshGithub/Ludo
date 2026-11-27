/// A quick chat message as it arrives from a room backend.
///
/// Only the sender's identity and the catalogue id travel over the network (see
/// `QuickChatCatalog`); the receiving device looks the id up and draws the
/// bubble itself.
class QuickChatEvent {
  const QuickChatEvent({
    required this.uid,
    required this.itemId,
    required this.nonce,
  });

  /// Player (Firebase uid, or the Wi-Fi install id) who sent the message. The
  /// backend fills this from the authenticated connection, never from the
  /// message body, so it cannot be spoofed.
  final String uid;

  /// `QuickChatItem.id`.
  final String itemId;

  /// Differs for every message a player sends. Lets a receiver drop a message
  /// it has already shown (Firestore reports one write more than once).
  final int nonce;
}
