import 'package:flutter/material.dart';

import '../engine/engine.dart';
import 'ludo_online_screen.dart';
import 'ludo_setup_screen.dart';
import 'ludo_theme.dart';

/// Hotspot / local Wi-Fi multiplayer: host a room or join one on the network.
/// Needs no internet connection.
class LudoLanMenuScreen extends StatelessWidget {
  const LudoLanMenuScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    return LudoScaffold(
      title: const Text('Hotspot / Wi-Fi'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                const SizedBox(height: 15),
                LudoModeButton(
                  icon: Icons.wifi_tethering_rounded,
                  title: 'Host a game',
                  subtitle: 'Use your hotspot or Wi-Fi to host a room for friends',
                  colors: const [Color(0xFF1E88E5), Color(0xFF0D47A1)],
                  onTap: () => _push(
                    context,
                    const LudoSetupScreen(mode: GameMode.online, onlineKind: OnlineEntry.lanHost),
                  ),
                ),
                LudoModeButton(
                  icon: Icons.wifi_find_rounded,
                  title: 'Join a game',
                  subtitle: 'Find rooms hosted on the same network',
                  colors: const [Color(0xFF43A047), Color(0xFF1B5E20)],
                  onTap: () => _push(context, const LudoOnlineScreen(entry: OnlineEntry.lanJoin)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
