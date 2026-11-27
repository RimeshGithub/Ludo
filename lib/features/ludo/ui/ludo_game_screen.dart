import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import '../state/ludo_controller.dart';
import 'board_view.dart';
import 'dice_widget.dart';
import 'ludo_results_screen.dart';
import 'ludo_style.dart';
import 'ludo_theme.dart';
import 'player_panel.dart';
import 'quick_chat_sheet.dart';
import 'seat_identity.dart';

/// The playing screen: board, dice, player cards, pause / restart / exit.
class LudoGameScreen extends ConsumerStatefulWidget {
  const LudoGameScreen({super.key});

  @override
  ConsumerState<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends ConsumerState<LudoGameScreen> with WidgetsBindingObserver {
  bool _resultsOpen = false;
  bool _hostLeftShown = false;
  bool _removedShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Backgrounding the app pauses a local game (and saves it).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      final ui = ref.read(ludoControllerProvider);
      if (ui.game != null && ui.game!.phase != LudoPhase.gameOver && ui.mode != GameMode.online) {
        ref.read(ludoControllerProvider.notifier).setPaused(true);
      }
    }
  }

  void _onState(LudoUiState? prev, LudoUiState next) {
    // Game was torn down (exit): remove this route wherever it sits in the stack.
    if (prev?.game != null && next.game == null) {
      final route = ModalRoute.of(context);
      if (route != null && mounted) Navigator.of(context).removeRoute(route);
      return;
    }

    final g = next.game;
    final pg = prev?.game;
    if (g == null) return;

    // Somebody left or was removed for inactivity: tell everyone still here.
    if (next.notice != null && next.noticeSeq != (prev?.noticeSeq ?? 0)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(next.notice!),
          duration: const Duration(seconds: 5),
        ));
    }

    // We were removed (too many missed turns): explain and go back to the menu.
    final me = next.mySeat;
    if (next.mode == GameMode.online &&
        me != null &&
        !g.isActive(me) &&
        !_removedShown) {
      _removedShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Removed from the game'),
          content: Text(
              'You missed ${LudoEngine.maxMissedTurns} turns in a row, so you were marked '
              'inactive and your tokens were removed from the board.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(ludoControllerProvider.notifier).exitGame();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Somebody just brought all of their tokens home.
    if (pg != null && g.ranking.length > pg.ranking.length && g.phase != LudoPhase.gameOver) {
      final team = g.ranking.last;
      final names = [
        for (var i = 0; i < g.config.playerCount; i++)
          if (g.config.teams[i] == team) g.config.seats[i].name,
      ].join(' & ');
      final text = isMyTeam(next, team)
          ? 'You finished in place ${g.ranking.length}!'
          : '$names finished in place ${g.ranking.length}!';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }

    if (g.phase == LudoPhase.gameOver && !_resultsOpen) {
      _resultsOpen = true;
      Future<void>.delayed(const Duration(milliseconds: 900), () async {
        if (!mounted) return;
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const LudoResultsScreen()));
        if (mounted) _resultsOpen = false;
      });
    }

    if (next.hostLeft && !_hostLeftShown) {
      _hostLeftShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(next.quick ? 'Player left' : 'Host left'),
          content: Text(next.quick
              ? 'A player left, so the game has ended.'
              : 'The host closed this room, so the game has ended.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.read(ludoControllerProvider.notifier).exitGame();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _exit() async {
    final ui = ref.read(ludoControllerProvider);
    final online = ui.mode == GameMode.online;
    final over = ui.game?.phase == LudoPhase.gameOver;
    final body = over
        ? 'Return to the menu?'
        : online
            ? 'If you leave, you are out of this game: your tokens are removed from the board '
                'and the others keep playing.'
            : 'Your progress is saved, so you can resume this game later.';
    if (await _confirm('Leave game?', body, 'Leave')) {
      await ref.read(ludoControllerProvider.notifier).exitGame();
    }
  }

  Future<void> _restart() async {
    if (await _confirm('Restart?', 'The current game will be lost.', 'Restart')) {
      ref.read(ludoControllerProvider.notifier).restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LudoUiState>(ludoControllerProvider, _onState);
    // `shown` changes on every step of a token walk; only the board reads it
    // (and it watches it itself). Ignoring it here keeps the player cards,
    // banner and app bar from rebuilding ~3 times a second during a move,
    // which is what made animations hitch on phones.
    final ui = ref.watch(ludoControllerProvider.select(_ScreenKey.new)).state;
    final ctrl = ref.read(ludoControllerProvider.notifier);
    final game = ui.game;
    if (game == null) return const Scaffold(body: SizedBox.shrink());

    final online = ui.mode == GameMode.online;
    final canRestart = !online; //|| (ui.isHost && !ui.quick);
    final isLan = ref.read(lanBackendProvider).address != null;
    // Quick chat: online / Wi-Fi games, for players who are still seated.
    final me = ui.mySeat;
    final canChat = online && me != null && game.isActive(me);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: LudoScaffold(
        title: Text(online
          ? (ui.quick
              ? 'Online game'
              : (isLan ? 'Wi-Fi game' : 'Room ${ui.roomCode ?? ''}'))
          : 'Local game'),
        actions: [
            if (canChat)
              IconButton(
                tooltip: 'Quick chat',
                icon: const Icon(Icons.chat_bubble_rounded),
                onPressed: () => showQuickChatSheet(context),
              ),
            IconButton(
              tooltip: ui.soundOn ? 'Mute' : 'Unmute',
              icon: Icon(ui.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded),
              onPressed: ctrl.toggleSound,
            ),
            if (!online)
              IconButton(
                tooltip: ui.paused ? 'Resume' : 'Pause',
                icon: Icon(ui.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                onPressed: () => ctrl.setPaused(!ui.paused),
              ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'restart') _restart();
                if (v == 'exit') _exit();
              },
              itemBuilder: (_) => [
                if (canRestart)
                  const PopupMenuItem(value: 'restart', child: Text('Restart')),
                const PopupMenuItem(value: 'exit', child: Text('Exit')),
              ],
            ),
        ],
        body: SafeArea(
          child: Stack(
            children: [
              _Body(ui: ui, ctrl: ctrl),
              if (ui.paused) _PauseOverlay(onResume: () => ctrl.setPaused(false), onRestart: _restart, onExit: _exit),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.ui, required this.ctrl});
  final LudoUiState ui;
  final LudoController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ui.game!;
    final diceSkin = ref.watch(ludoStyleProvider.select((s) => s.diceSkin));

    // 5-6 players: 3 rows x 2 columns on wide screens (Windows / tablets) and
    // 2 rows x 3 columns on phones. Up to 4 players: a 2 x 2 grid. No scrolling.
    Widget cards({required bool wide}) {
      final n = game.config.playerCount;
      final columns = (!wide && n >= 5) ? 3 : 2;
      // Team mode: list teammates next to each other (same team = adjacent
      // cards), instead of in seat order where partners sit far apart.
      final order = [for (var s = 0; s < n; s++) s];
      if (game.config.teamMode) {
        order.sort((a, b) {
          final byTeam = game.teamOf(a).compareTo(game.teamOf(b));
          return byTeam != 0 ? byTeam : a.compareTo(b);
        });
      }
      return _PlayerGrid(
        columns: columns,
        children: [
          for (final s in order)
            (bool compact) => PlayerCard(
                  game: game,
                  seat: s,
                  isCurrent: game.phase != LudoPhase.gameOver && s == game.currentSeat,
                  // "(you)": see [isMySeat].
                  isMe: isMySeat(ui, s),
                  dense: true,
                  compact: compact,
                ),
        ],
      );
    }

    final cur = game.currentSeat;
    final curColor = LudoPalette.seat(game.config.layout.colorIndexOfSeat(cur));
    // The die animates continuously: its own layer keeps that from repainting
    // the board and the rest of the screen.
    final dice = RepaintBoundary(
      child: DiceWidget(
        value: ui.diceFace,
        rolling: ui.rolling,
        enabled: ctrl.canRoll,
        accent: curColor,
        onTap: ctrl.rollTapped,
        skin: diceSkin,
        size: 84,
      ),
    );
    final banner = RepaintBoundary(
      child: _TurnBanner(ui: ui, canRoll: ctrl.canRoll, canPick: ctrl.canPickToken),
    );

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 820 && box.maxWidth > box.maxHeight * 1.1;
      if (wide) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Board
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: LudoBoardView(),
                  ),
                ),
              ),

              // Player list and dice
              SizedBox(
                width: 340,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(child: cards(wide: true)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 120,
                          child: Center(child: banner),
                        ),
                        const SizedBox(height: 12),
                        Center(child: dice),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: cards(wide: false),
          ),
          const Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Center(child: LudoBoardView()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              height: 120,
              child: Row(
                children: [
                  dice,
                  const SizedBox(width: 14),
                  Expanded(child: banner),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.ui, required this.canRoll, required this.canPick});
  final LudoUiState ui;
  final bool canRoll;
  final bool canPick;

  @override
  Widget build(BuildContext context) {
    final g = ui.game!;
    if (g.phase == LudoPhase.gameOver) {
      return const _Banner(color: LudoPalette.gold, title: 'Game over', subtitle: null);
    }
    final seat = g.config.seats[g.currentSeat];
    final color = LudoPalette.seat(g.config.layout.colorIndexOfSeat(g.currentSeat));
    final mine = isMySeat(ui, g.currentSeat);

    String hint;
    if (ui.paused) {
      hint = 'Game paused';
    } else if (canRoll) {
      hint = 'Tap the dice to roll';
    } else if (canPick) {
      hint = 'Tap a highlighted token';
    } else if (seat.isBot) {
      hint = 'Computer is playing…';
    } else if (ui.mode == GameMode.online && !mine) {
      hint = 'Waiting for ${seat.name}…';
    } else {
      hint = '';
    }
    final title = mine ? 'Your turn' : "${seat.name}'s turn";
    final sub = ui.message ?? (hint.isEmpty ? null : hint);
    final endsAt = ui.turnEndsAt;
    return _Banner(
      color: color,
      title: title,
      subtitle: sub,
      trailing: endsAt == null || ui.paused
          ? null
          : RepaintBoundary(child: _Countdown(endsAt: endsAt)),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.title, required this.subtitle, this.trailing});
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [LudoPalette.panel, Color.lerp(LudoPalette.panel, color, 0.45)!]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
                ),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Seconds left for the current player's move; turns red in the last 10s.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.endsAt});
  final int endsAt;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leftMs = widget.endsAt - DateTime.now().millisecondsSinceEpoch;
    final secs = leftMs <= 0 ? 0 : (leftMs / 1000).ceil();
    final urgent = secs <= 10;
    final color = urgent ? Colors.redAccent : Colors.white;
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black26,
        border: Border.all(color: color, width: 2.5),
      ),
      child: Text(
        '$secs',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onRestart, required this.onExit});
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Paused', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Resume'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: onRestart,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Restart'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onExit,
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('Exit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-width grid of player cards (no scrolling). Each child builds its card
/// and is told whether the cell is narrow enough to need the compact layout.
class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget Function(bool compact)> children;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cellWidth = (box.maxWidth - _gap * (columns - 1)) / columns;
      final compact = cellWidth < 190;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += columns) {
        final cells = <Widget>[];
        for (var c = 0; c < columns; c++) {
          if (c > 0) cells.add(const SizedBox(width: _gap));
          final idx = i + c;
          cells.add(Expanded(
            child: idx < children.length ? children[idx](compact) : const SizedBox.shrink(),
          ));
        }
        if (rows.isNotEmpty) rows.add(const SizedBox(height: _gap));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    });
  }
}

/// Wraps the UI state with an equality that ignores [LudoUiState.shown], so a
/// `select` on it only fires when something other than the token animation
/// changed.
class _ScreenKey {
  const _ScreenKey(this.state);
  final LudoUiState state;

  @override
  bool operator ==(Object other) {
    if (other is! _ScreenKey) return false;
    final a = state, b = other.state;
    return identical(a.game, b.game) &&
        a.mode == b.mode &&
        a.busy == b.busy &&
        a.rolling == b.rolling &&
        a.diceFace == b.diceFace &&
        a.paused == b.paused &&
        a.soundOn == b.soundOn &&
        a.message == b.message &&
        a.mySeat == b.mySeat &&
        a.isHost == b.isHost &&
        a.roomCode == b.roomCode &&
        a.hostLeft == b.hostLeft &&
        a.quick == b.quick &&
        a.turnEndsAt == b.turnEndsAt &&
        a.notice == b.notice &&
        a.noticeSeq == b.noticeSeq;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(state.game), state.mode, state.busy,
      state.rolling, state.diceFace, state.paused, state.noticeSeq);
}
