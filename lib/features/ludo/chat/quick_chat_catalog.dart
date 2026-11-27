/// Quick Chat catalogue: every message and emoji a player can send.
///
/// ## Adding your own
///
/// Add one line to [QuickChatCatalog.items]. That is all: the picker sheet, the
/// board bubbles and both multiplayer backends (online and Wi-Fi) pick it up.
///
/// ```dart
/// QuickChatItem('rematch', text: 'Rematch?', emoji: '🔁', category: QuickChatCategory.message),
/// QuickChatItem('party',   emoji: '🥳',                    category: QuickChatCategory.reaction),
/// ```
///
/// Rules for items:
///  * [QuickChatItem.id] travels over the network instead of the text, so the
///    text can be reworded or translated later without breaking anything. Keep
///    it short (see [QuickChatConfig.maxIdLength]), lowercase, and **never
///    change or reuse the id of a shipped item**.
///  * An item needs [QuickChatItem.text], [QuickChatItem.emoji], or both. Emoji
///    only items are drawn large in the bubble.
///  * An id this build does not know is ignored, so a newer app can safely chat
///    with an older one.
///  * Adding a new [QuickChatCategory] value adds a new section to the picker.
library;

/// A section of the picker sheet.
enum QuickChatCategory {
  message('Messages'),
  reaction('Reactions');

  const QuickChatCategory(this.label);

  /// Heading shown above the section in the picker.
  final String label;
}

/// One thing a player can say.
class QuickChatItem {
  const QuickChatItem(
    this.id, {
    this.text,
    this.emoji,
    required this.category,
  }) : assert(text != null || emoji != null, 'A quick chat item needs text or an emoji');

  /// Stable wire identifier (see the library notes above).
  final String id;

  /// Words shown in the bubble, e.g. `Nice!`.
  final String? text;

  /// Emoji shown in the bubble, alone or in front of [text].
  final String? emoji;

  final QuickChatCategory category;
}

/// Tunables for the feature.
abstract final class QuickChatConfig {
  /// How long a bubble stays on the board. A new message from the same player
  /// replaces the old bubble and restarts this time.
  static const Duration bubbleDuration = Duration(seconds: 4);

  /// Minimum time between two messages from the same player (sender side).
  static const Duration sendCooldown = Duration(milliseconds: 1200);

  /// Wi-Fi host: messages from one player closer together than this are dropped.
  static const Duration minRelayGap = Duration(milliseconds: 500);

  /// Longest allowed item id. Mirrored in `firestore.rules`.
  static const int maxIdLength = 32;
}

/// All items, in the order they appear in the picker.
abstract final class QuickChatCatalog {
  static const List<QuickChatItem> items = [
    // ------------------------------------------------------------- messages
    QuickChatItem('nice', text: 'Nice!', emoji: '👏', category: QuickChatCategory.message),
    QuickChatItem('haha', text: 'Haha!', emoji: '🤣', category: QuickChatCategory.message),
    QuickChatItem('oops', text: 'Oops!', emoji: '🙈', category: QuickChatCategory.message),
    QuickChatItem('gg', text: 'Good game!', emoji: '🤝', category: QuickChatCategory.message),
    QuickChatItem('good_luck', text: 'Good luck!', emoji: '🍀', category: QuickChatCategory.message),
    QuickChatItem('hurry', text: 'Hurry up!', emoji: '⏰', category: QuickChatCategory.message),
    QuickChatItem('well_played', text: 'Well played!', emoji: '💪', category: QuickChatCategory.message),
    QuickChatItem('unlucky', text: 'So unlucky!', emoji: '😞', category: QuickChatCategory.message),
    QuickChatItem('thanks', text: 'Thanks!', emoji: '🙏', category: QuickChatCategory.message),
    QuickChatItem('sorry', text: 'Sorry!', emoji: '😔', category: QuickChatCategory.message),
    QuickChatItem('wow', text: 'Wow!', emoji: '😮', category: QuickChatCategory.message),
    QuickChatItem('fuck', text: 'Fuck!', emoji: '🤬', category: QuickChatCategory.message),

    // ------------------------------------------------------------ reactions
    QuickChatItem('laugh', emoji: '😂', category: QuickChatCategory.reaction),
    QuickChatItem('thumbs_up', emoji: '👍', category: QuickChatCategory.reaction),
    QuickChatItem('clap', emoji: '👏', category: QuickChatCategory.reaction),
    QuickChatItem('cool', emoji: '😎', category: QuickChatCategory.reaction),
    QuickChatItem('love', emoji: '❤️', category: QuickChatCategory.reaction),
    QuickChatItem('fire', emoji: '🔥', category: QuickChatCategory.reaction),
    QuickChatItem('party', emoji: '🎉', category: QuickChatCategory.reaction),
    QuickChatItem('wow_face', emoji: '😮', category: QuickChatCategory.reaction),
    QuickChatItem('think', emoji: '🤔', category: QuickChatCategory.reaction),
    QuickChatItem('sweat', emoji: '😅', category: QuickChatCategory.reaction),
    QuickChatItem('cry', emoji: '😭', category: QuickChatCategory.reaction),
    QuickChatItem('silly', emoji: '🤪', category: QuickChatCategory.reaction),
    QuickChatItem('meh', emoji: '😑', category: QuickChatCategory.reaction),
    QuickChatItem('angry', emoji: '😡', category: QuickChatCategory.reaction),
    QuickChatItem('angry2', emoji: '🤬', category: QuickChatCategory.reaction),
  ];

  static final Map<String, QuickChatItem> _byId = {
    for (final i in items) i.id: i,
  };

  /// The item with [id], or null for an id this build does not know.
  static QuickChatItem? byId(String id) => _byId[id];

  /// Items of one picker section, in catalogue order.
  static List<QuickChatItem> inCategory(QuickChatCategory c) =>
      [for (final i in items) if (i.category == c) i];
}
