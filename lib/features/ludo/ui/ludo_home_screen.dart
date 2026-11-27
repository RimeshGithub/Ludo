import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import 'ludo_game_screen.dart';
import 'ludo_lan_menu_screen.dart';
import 'ludo_online_menu_screen.dart';
import 'ludo_setup_screen.dart';
import 'ludo_theme.dart';
import 'player_name_dialog.dart';
import 'theme_picker.dart';

/// First screen of the Ludo mode: one big button per game mode, plus the
/// interrupted local game (resume / delete). Tapping a mode opens its options.
class LudoHomeScreen extends ConsumerStatefulWidget {
  const LudoHomeScreen({super.key});

  @override
  ConsumerState<LudoHomeScreen> createState() => _LudoHomeScreenState();
}

class _LudoHomeScreenState extends ConsumerState<LudoHomeScreen> {
  bool _asked = false;

  /// First launch: the player must pick a display name before anything else.
  void _askNameIfNeeded(AsyncValue<String?> name) {
    if (_asked || !name.hasValue || name.value != null) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final picked = await showPlayerNameDialog(context, required: true);
      if (picked != null)
        await ref.read(playerNameProvider.notifier).setName(picked);
    });
  }

  Future<void> _editName(String? current) async {
    final picked = await showPlayerNameDialog(context, initial: current);
    if (picked != null)
      await ref.read(playerNameProvider.notifier).setName(picked);
  }

  Future<void> _openMode(BuildContext context, GameMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => mode == GameMode.online
            ? const LudoOnlineMenuScreen()
            : LudoSetupScreen(mode: mode),
      ),
    );
    ref.invalidate(savedGameProvider);
  }

  Future<void> _openLan(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LudoLanMenuScreen()));
    ref.invalidate(savedGameProvider);
  }

  Future<void> _resume(BuildContext context) async {
    final ok = await ref.read(ludoControllerProvider.notifier).resume();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No saved game found')));
      ref.invalidate(savedGameProvider);
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LudoGameScreen()));
    ref.invalidate(savedGameProvider);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved game?'),
        content: const Text(
          'This removes your interrupted game. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(ludoStoreProvider).clearGame();
    ref.invalidate(savedGameProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved game deleted')));
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final nameAsync = ref.watch(playerNameProvider);
    _askNameIfNeeded(nameAsync);
    final myName = nameAsync.valueOrNull;
    final saved = ref.watch(savedGameProvider).valueOrNull;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Colors.white60);

    final soundOn = ref.watch(ludoControllerProvider.select((s) => s.soundOn));

    final modes = <Widget>[
      LudoModeButton(
        icon: Icons.people_alt_rounded,
        title: 'Local multiplayer',
        subtitle: 'Pass the device between 2 to 6 players',
        colors: const [Color(0xFF43A047), Color(0xFF1B5E20)],
        onTap: () => _openMode(context, GameMode.local),
      ),
      LudoModeButton(
        icon: Icons.smart_toy_rounded,
        title: 'Play vs AI',
        subtitle: 'Bots with easy, medium or hard difficulty',
        colors: const [Color(0xFF1E88E5), Color(0xFF0D47A1)],
        onTap: () => _openMode(context, GameMode.ai),
      ),
      LudoModeButton(
        icon: Icons.public_rounded,
        title: 'Online multiplayer',
        subtitle: 'Quick Start, private rooms or join with a code',
        colors: const [Color(0xFFFB8C00), Color(0xFFE65100)],
        onTap: () => _openMode(context, GameMode.online),
      ),
      LudoModeButton(
        icon: Icons.wifi_tethering_rounded,
        title: 'Hotspot / Wi-Fi',
        subtitle: 'Play with nearby friends, no internet needed',
        colors: const [Color(0xFF8E24AA), Color(0xFF4A148C)],
        onTap: () => _openLan(context),
      ),
    ];

    final Widget namePanel = LudoPanel(
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: LudoPalette.accent,
            child: Icon(Icons.person_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Playing as', style: muted),
                Text(
                  myName ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit name',
            icon: const Icon(Icons.edit_rounded, size: 30),
            onPressed: myName == null ? null : () => _editName(myName),
          ),
        ],
      ),
    );
    final Widget? savedPanel = saved == null
        ? null
        : LudoPanel(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: LudoPalette.accent,
                  child: Icon(Icons.history_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saved ${saved.state.config.playerCount}-player game',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text('Saved ${_ago(saved.savedAt)}', style: muted),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete saved game',
                  color: Colors.red.shade700,
                  icon: const Icon(Icons.delete_outline_rounded, size: 30),
                  onPressed: () => _delete(context),
                ),
                IconButton(
                  tooltip: 'Resume saved game',
                  icon: const Icon(Icons.play_arrow_rounded, size: 30),
                  onPressed: () => _resume(context),
                ),
              ],
            ),
          );

    return LudoScaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // Wide screens (tablets, Windows): game modes in a 2 x 2 grid.
            final wide = box.maxWidth >= 760;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 900 : 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    Stack(
                      children: [
                        const _Hero(),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: soundOn ? 'Sound on' : 'Sound off',
                                icon: Icon(
                                  soundOn
                                      ? Icons.volume_up_rounded
                                      : Icons.volume_off_rounded,
                                      size: 35,
                                ),
                                onPressed: ref
                                    .read(ludoControllerProvider.notifier)
                                    .toggleSound,
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                tooltip: 'Theme',
                                icon: const Icon(Icons.palette_rounded, size: 35),
                                onPressed: () => showThemePicker(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (wide && savedPanel != null)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: namePanel),
                            const SizedBox(width: 14),
                            Expanded(child: savedPanel),
                          ],
                        ),
                      )
                    else ...[
                      namePanel,
                      if (savedPanel != null) savedPanel,
                    ],
                    if (wide)
                      for (var i = 0; i < modes.length; i += 2)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: modes[i]),
                              const SizedBox(width: 14),
                              Expanded(
                                child: i + 1 < modes.length
                                    ? modes[i + 1]
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        )
                    else
                      ...modes,
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 70, 0, 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: LudoPalette.seat(i == 2 ? 2 : (i == 3 ? 3 : i)),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'LUDO',
            style: TextStyle(
              fontSize: 54,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black38,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Roll. Race. Capture. 2 to 6 players.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}