import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/quick_chat_catalog.dart';
import '../state/quick_chat_controller.dart';
import 'ludo_theme.dart';

/// Opens the quick chat picker. Picking an item sends it and closes the sheet,
/// so the player is straight back in the game.
Future<void> showQuickChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: LudoPalette.panel,
    // Keeps the sheet a sensible width on wide (Windows / tablet) screens.
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const QuickChatSheet(),
  );
}

/// The picker: one section per [QuickChatCategory], built from
/// [QuickChatCatalog], so new items and categories show up without any change
/// here.
class QuickChatSheet extends ConsumerStatefulWidget {
  const QuickChatSheet({super.key});

  @override
  ConsumerState<QuickChatSheet> createState() => _QuickChatSheetState();
}

class _QuickChatSheetState extends ConsumerState<QuickChatSheet> {
  bool _tooFast = false;

  void _pick(QuickChatItem item) {
    final sent = ref.read(quickChatProvider.notifier).send(item.id);
    if (sent) {
      Navigator.of(context).pop();
    } else if (!_tooFast) {
      // Still in the short cooldown after the previous message.
      setState(() => _tooFast = true);
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _tooFast = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.chat_bubble_rounded, color: LudoPalette.accent, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Quick chat',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const Spacer(),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _tooFast ? 1 : 0,
                  child: const Text(
                    'Not so fast…',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
            for (final category in QuickChatCategory.values)
              ..._section(category),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(QuickChatCategory category) {
    final items = QuickChatCatalog.inCategory(category);
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(
        category.label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, box) {
          const gap = 8.0;
          final w = (box.maxWidth - gap * 2) / 3; // 3 equal columns
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                SizedBox(width: w, child: _ItemButton(item: item, onTap: () => _pick(item))),
            ],
          );
        },
      ),
    ];
  }
}

class _ItemButton extends StatelessWidget {
  const _ItemButton({required this.item, required this.onTap});

  final QuickChatItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emojiOnly = item.text == null;
    return Material(
      color: LudoPalette.field,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          alignment: Alignment.center,
          // Fills its grid cell; long labels shrink instead of overflowing.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.emoji != null)
                  Text(item.emoji!, style: TextStyle(fontSize: emojiOnly ? 22 : 20)),
                if (item.emoji != null && item.text != null) const SizedBox(width: 8),
                if (item.text != null)
                  Text(
                    item.text!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}