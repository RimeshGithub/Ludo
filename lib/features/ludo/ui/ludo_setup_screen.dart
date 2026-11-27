import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import 'board_painter.dart';
import 'ludo_style.dart';
import 'ludo_game_screen.dart';
import 'ludo_online_screen.dart';
import 'ludo_theme.dart';

/// Entry screen of the Ludo mode: choose mode, player count, names, bots,
/// teams and rule options, or resume an interrupted local game.
class LudoSetupScreen extends ConsumerStatefulWidget {
  const LudoSetupScreen({super.key, required this.mode, this.onlineKind});

  /// Which game mode these options configure (chosen on the home screen).
  final GameMode mode;

  /// For online mode: Quick Start or Create Room (see [OnlineEntry]).
  final OnlineEntry? onlineKind;

  @override
  ConsumerState<LudoSetupScreen> createState() => _LudoSetupScreenState();
}

class _LudoSetupScreenState extends ConsumerState<LudoSetupScreen> {
  static const _maxName = 12;

  late GameMode _mode;
  int _count = 4;
  final List<TextEditingController> _names =
      List.generate(6, (i) => TextEditingController(text: 'Player ${i + 1}'));
  final List<bool> _bot = List<bool>.filled(6, false);
  final List<BotLevel> _level = List<BotLevel>.filled(6, BotLevel.medium);

  bool _teams = false;
  int _preset = 0;
  bool _bonusCapture = true;
  bool _bonusFinish = true;
  bool _bonusOne = false;
  bool _enterOne = false;
  bool _oneTokenOut = false;
  bool _stackedCapture = true;
  bool _threeSixes = true;
  bool _bounceBack = false;
  bool _rankAll = true;
  int _tokens = 4;
  int _turnSeconds = 30; // online only; 0 = no limit

  @override
  void initState() {
    super.initState();
    final mine = ref.read(playerNameProvider).valueOrNull;
    if (mine != null) _names[0].text = mine; // seat 1 is the player
    _applyMode(widget.mode);
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  String _humanName(int i) => 'Player ${i + 1}';
  String _botName(int i) => 'Bot ${i + 1}';

  void _setBot(int i, bool bot) {
    _bot[i] = bot;
    final t = _names[i].text.trim();
    if (t == _humanName(i) || t == _botName(i) || t.isEmpty) {
      _names[i].text = bot ? _botName(i) : _humanName(i);
    }
  }

  void _applyMode(GameMode mode) {
    _mode = mode;
    for (var i = 0; i < 6; i++) {
      _setBot(i, mode == GameMode.ai && i > 0);
    }
  }

  BoardLayout get _layout => BoardLayout.forPlayers(_count);

  void _setCount(int n) {
    setState(() {
      _count = n;
      final presets = _layout.teamPresets;
      if (presets.isEmpty) _teams = false;
      if (_preset >= presets.length) _preset = 0;
    });
  }

  String _nameOf(int i) {
    final t = _names[i].text.trim();
    if (t.isEmpty) return _bot[i] ? _botName(i) : _humanName(i);
    return t.length > _maxName ? t.substring(0, _maxName) : t;
  }

  List<int>? get _teamMap {
    final presets = _layout.teamPresets;
    if (!_teams || presets.isEmpty) return null;
    return presets[_preset].teamOfSeat;
  }

  void _startLocal() {
    final seats = [
      for (var i = 0; i < _count; i++)
        SeatConfig(
          name: _nameOf(i),
          kind: _bot[i] ? PlayerKind.bot : PlayerKind.human,
          level: _level[i],
        ),
    ];
    if (seats.every((s) => s.isBot)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one seat must be a human player')),
      );
      return;
    }
    final config = GameConfig(
      seats: seats,
      teams: _teamMap,
      bonusOnCapture: _bonusCapture,
      bonusOnFinish: _bonusFinish,
      bonusOnOne: _bonusOne,
      enterOnOne: _enterOne,
      rankAll: _rankAll,
      tokenCount: _tokens,
      oneTokenOut: _oneTokenOut,
      stackedCapture: _stackedCapture,
      threeSixesForfeit: _threeSixes,
      bounceBack: _bounceBack,
    );
    ref.read(ludoControllerProvider.notifier).startLocal(config, _mode);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LudoGameScreen()));
  }

  void _resetDefaults() {
    setState(() {
      _teams = false;
      _preset = 0;
      _bonusCapture = true;
      _bonusFinish = true;
      _bonusOne = false;
      _enterOne = false;
      _oneTokenOut = false;
      _stackedCapture = true;
      _threeSixes = true;
      _bounceBack = false;
      _rankAll = true;
      _tokens = 4;
      _turnSeconds = 30;
    });
  }

  void _openOnline() {
    final presets = _layout.teamPresets;
    final settings = OnlineSettings(
      hostName: ref.read(playerNameProvider).valueOrNull ?? 'Player',
      playerCount: _count,
      teamPreset: _teams && presets.isNotEmpty ? _preset : -1,
      bonusOnCapture: _bonusCapture,
      bonusOnFinish: _bonusFinish,
      bonusOnOne: _bonusOne,
      enterOnOne: _enterOne,
      rankAll: _rankAll,
      tokenCount: _tokens,
      oneTokenOut: _oneTokenOut,
      stackedCapture: _stackedCapture,
      threeSixesForfeit: _threeSixes,
      bounceBack: _bounceBack,
      turnSeconds: _turnSeconds,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LudoOnlineScreen(
          entry: widget.onlineKind ?? OnlineEntry.create,
          settings: settings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final presets = layout.teamPresets;
    final online = _mode == GameMode.online;
    final quick = online && widget.onlineKind == OnlineEntry.quick;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    final title = switch (_mode) {
      GameMode.local => 'Local multiplayer',
      GameMode.ai => 'Play vs AI',
      GameMode.online =>
        widget.onlineKind == OnlineEntry.quick
            ? 'Quick Start'
            : (widget.onlineKind == OnlineEntry.lanHost ? 'Host Wi-Fi game' : 'Create room'),
    };

    return LudoScaffold(
      title: Text(title),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                LudoPanel(
                  title: 'Players',
                  icon: Icons.groups_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: [
                            for (var n = 2; n <= 6; n++)
                              ButtonSegment<int>(
                                value: n,
                                label: Text('$n'),
                              ),
                          ],
                          selected: {_count},
                          onSelectionChanged: (v) => _setCount(v.first),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _BoardPreview(layout: layout),
                    ],
                  ),
                ),
                if (!online)
                LudoPanel(
                  title: 'Seats',
                  icon: Icons.badge_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Tip: tap the person / robot button next to a seat to switch it '
                                'between a human and a computer player.\n',
                                style: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < _count; i++)
                        _seatRow(i, allowBot: true), 
                    ],
                  ),
                ),
                LudoPanel(
                  title: 'Rules',
                  icon: Icons.tune_rounded,
                  trailing: TextButton.icon(
                    onPressed: _resetDefaults,
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Default'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (presets.isEmpty)
                        Text(
                          'Team mode is not available on the ${layout.name} board '
                          '($_count players). Try 4 or 6 players.\n',
                          style: muted,
                        )
                      else ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Team mode'),
                          subtitle: const Text(
                              'Partners win together and move each other\'s tokens once their own are home'),
                          value: _teams,
                          onChanged: (v) => setState(() => _teams = v),
                        ),
                        if (_teams && presets.length == 1)
                          // Only one team layout exists, so a dropdown would be
                          // pointless: show it as hint text instead.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 16, color: Colors.white60),
                                const SizedBox(width: 6),
                                Expanded(child: Text(presets.first.label, style: muted)),
                              ],
                            ),
                          )
                        else if (_teams)
                          DropdownButton<int>(
                            isExpanded: true,
                            value: _preset,
                            items: [
                              for (var i = 0; i < presets.length; i++)
                                DropdownMenuItem(value: i, child: Text(presets[i].label)),
                            ],
                            onChanged: (v) => setState(() => _preset = v ?? 0),
                          ),
                        const Divider(),
                      ],
                      Text('Tokens per player', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: [
                            for (var n = 1; n <= 4; n++)
                              ButtonSegment<int>(value: n, label: Text('$n')),
                          ],
                          selected: {_tokens},
                          onSelectionChanged: (v) => setState(() => _tokens = v.first),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Roll again after a capture'),
                        value: _bonusCapture,
                        onChanged: (v) => setState(() => _bonusCapture = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Roll again after a token reaches home'),
                        value: _bonusFinish,
                        onChanged: (v) => setState(() => _bonusFinish = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Roll again after rolling a 1'),
                        subtitle: const Text('A 6 always gives another roll'),
                        value: _bonusOne,
                        onChanged: (v) => setState(() => _bonusOne = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('A 1 also brings a token out of the yard'),
                        subtitle: const Text('Normally only a 6 does'),
                        value: _enterOne,
                        onChanged: (v) => setState(() => _enterOne = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('One Token Out'),
                        subtitle: const Text('Every player starts with one token already out'),
                        value: _oneTokenOut,
                        onChanged: (v) => setState(() => _oneTokenOut = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Stacked capture'),
                        subtitle: const Text(
                            'Landing on two or more opponent tokens captures them all. When off, such a stack is safe'),
                        value: _stackedCapture,
                        onChanged: (v) => setState(() => _stackedCapture = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Three sixes forfeit'),
                        subtitle: const Text('Rolling three 6s in a row ends the turn with no move'),
                        value: _threeSixes,
                        onChanged: (v) => setState(() => _threeSixes = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Bounce back at home'),
                        subtitle: const Text('Overshooting home bounces the token back instead of needing an exact roll'),
                        value: _bounceBack,
                        onChanged: (v) => setState(() => _bounceBack = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Play on until every rank is decided'),
                        value: _rankAll,
                        onChanged: (v) => setState(() => _rankAll = v),
                      ),
                      if (online) ...[
                        const Divider(),
                        Text('Time per move', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text('When time runs out the move is played automatically',
                            style: muted),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<int>(value: 15, label: Text('15s')),
                              ButtonSegment<int>(value: 30, label: Text('30s')),
                              ButtonSegment<int>(value: 60, label: Text('60s')),
                              ButtonSegment<int>(value: 0, label: Text('No limit')),
                            ],
                            selected: {_turnSeconds},
                            onSelectionChanged: (v) => setState(() => _turnSeconds = v.first),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _StartButton(
                  online: online,
                  label: !online ? 'START GAME' : (quick ? 'FIND MATCH' : 'CREATE ROOM'),
                  onPressed: online ? _openOnline : _startLocal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _levelMenu(BotLevel value, ValueChanged<BotLevel> onChanged) {
    return DropdownButton<BotLevel>(
      value: value,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: BotLevel.easy, child: Text('Easy')),
        DropdownMenuItem(value: BotLevel.medium, child: Text('Medium')),
        DropdownMenuItem(value: BotLevel.hard, child: Text('Hard')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _seatRow(int i, {required bool allowBot}) {
    final color = LudoPalette.seat(_layout.colorIndexOfSeat(i));
    final teamMap = _teamMap;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Tooltip(
            message: LudoPalette.name(_layout.colorIndexOfSeat(i)),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: color,
              child: teamMap == null
                  ? null
                  : Text(LudoPalette.teamName(teamMap[i]),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _names[i],
              maxLength: _maxName,
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                labelText: 'Name',
                filled: true,
                fillColor: LudoPalette.field,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (allowBot) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: _bot[i] ? 'Computer player' : 'Human player',
              isSelected: _bot[i],
              icon: const Icon(Icons.person_rounded),
              selectedIcon: const Icon(Icons.smart_toy_rounded),
              onPressed: () => setState(() => _setBot(i, !_bot[i])),
            ),
            const SizedBox(width: 6),
            if (_bot[i]) _levelMenu(_level[i], (l) => setState(() => _level[i] = l)),
          ],
          const SizedBox(height: 55),
        ],
      ),
    );
  }

}

class _BoardPreview extends ConsumerWidget {
  const _BoardPreview({required this.layout});
  final BoardLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LudoPalette.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(painter: BoardPainter(layout, ref.watch(ludoStyleProvider))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(layout.name, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(layout.description, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    'Track: ${layout.ringLength} cells\n'
                    'Safe squares: ${layout.safeCells.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _CountButton extends StatelessWidget {
  const _CountButton({required this.n, required this.selected, required this.onTap});
  final int n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [LudoPalette.accent, Color(0xFFFF6F00)],
                )
              : null,
          color: selected ? null : LudoPalette.field,
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x66FF6F00), blurRadius: 12, offset: Offset(0, 4))]
              : const [],
        ),
        alignment: Alignment.center,
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.online, required this.label, required this.onPressed});
  final bool online;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF6F00)]),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: SizedBox(
            height: 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(online ? Icons.bolt_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
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