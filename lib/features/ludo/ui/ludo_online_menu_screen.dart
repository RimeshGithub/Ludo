import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'ludo_online_screen.dart';
import 'ludo_setup_screen.dart';
import 'ludo_theme.dart';

/// Online multiplayer menu: Quick Start, Create Room, Join Room.
class LudoOnlineMenuScreen extends StatelessWidget {
  const LudoOnlineMenuScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return LudoScaffold(
      title: const Text('Online multiplayer'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                const SizedBox(height: 15),
                LudoModeButton(
                  icon: Icons.bolt_rounded,
                  title: 'Quick Start',
                  subtitle: 'Pick number of players and rules, get matched automatically',
                  colors: const [Color(0xFFFB8C00), Color(0xFFE65100)],
                  onTap: () => _push(
                    context,
                    const LudoSetupScreen(mode: GameMode.online, onlineKind: OnlineEntry.quick),
                  ),
                ),
                LudoModeButton(
                  icon: Icons.meeting_room_rounded,
                  title: 'Create Room',
                  subtitle: 'Private room with your own rules and a shareable code for friends',
                  colors: const [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                  onTap: () => _push(
                    context,
                    const LudoSetupScreen(mode: GameMode.online, onlineKind: OnlineEntry.create),
                  ),
                ),
                LudoModeButton(
                  icon: Icons.login_rounded,
                  title: 'Join Room',
                  subtitle: 'Enter a shareable code to join a room',
                  colors: const [Color(0xFF43A047), Color(0xFF1B5E20)],
                  onTap: () => _push(context, const LudoOnlineScreen(entry: OnlineEntry.join)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
