import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';
import 'board_painter.dart';
import 'dice_widget.dart';
import 'ludo_style.dart';
import 'ludo_theme.dart';
import 'token_painter.dart';

/// Bottom sheet where the player picks the board theme, fine-tunes it and
/// chooses the token and dice look.
Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: LudoPalette.panel,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 680),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _ThemeSheet(),
  );
}

const Color _lavender = Color(0xFFB39DDB);

/// Colours offered for the surface / frame / track overrides.
const List<Color> _swatches = [
  Color(0xFFFFFFFF),
  Color(0xFFF6E7C1),
  Color(0xFFE8D2A6),
  Color(0xFFFFCC80),
  Color(0xFFF8C8DC),
  Color(0xFFD1C4E9),
  Color(0xFFB3E0F2),
  Color(0xFFC3DBA6),
  Color(0xFF2A7F7F),
  Color(0xFF546E7A),
  Color(0xFF6D2C3E),
  Color(0xFF2B2B4A),
  Color(0xFF14142B),
];

class _ThemeSheet extends ConsumerWidget {
  const _ThemeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(ludoStyleProvider);
    final ctrl = ref.read(ludoStyleProvider.notifier);
    final theme = BoardStyle.all[style.board.clamp(0, BoardStyle.all.length - 1)];
    final custom = style.custom;
    final layout = BoardLayout.forPlayers(4);

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: Column(
          children: [
            // Live preview stays visible while scrolling through the options.
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 0, 25, 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: LudoPalette.field,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 180,
                          height: 180,
                          child: CustomPaint(painter: BoardPainter(layout, style)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CURRENT THEME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            theme.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                          ),
                          // const SizedBox(height: 8),
                          // _StatusPill(customised: !custom.isEmpty),
                          const SizedBox(height: 18),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              shape: const StadiumBorder(),
                            ),
                            icon: const Icon(Icons.restart_alt_rounded, size: 18),
                            label: const Text('Reset', style: TextStyle(fontSize: 14)),
                            onPressed: custom.isEmpty ? null : ctrl.resetCustom,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(30, 4, 30, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Heading('Tokens', 'Choose how your pieces look'),
                    const SizedBox(height: 12),
                    _ChoiceGrid(
                      children: [
                        for (final t in TokenStyle.values)
                          _Choice(
                            label: t.label,
                            selected: style.token == t,
                            onTap: () => ctrl.setToken(t),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final c in const [0, 3])
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: CustomPaint(painter: TokenPainter(t, LudoPalette.seat(c))),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const _Heading('Dice', 'Choose how your dice look'),
                    const SizedBox(height: 12),
                    _ChoiceGrid(
                      children: [
                        for (final d in DiceStyle.values)
                          _Choice(
                            label: d.label,
                            selected: style.dice == d,
                            onTap: () => ctrl.setDice(d),
                            child: DiceFace(
                              value: 5,
                              size: 52,
                              skin: DiceSkin.of(d).withPip(custom.pick(CustomKey.pip, PipShape.values)),
                              accent: LudoPalette.seat(0),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const _Heading('Board theme', 'Pick a base look'),
                    const SizedBox(height: 12),
                    _ChoiceGrid(
                      children: [
                        for (var i = 0; i < BoardStyle.all.length; i++)
                          _Choice(
                            label: BoardStyle.all[i].name,
                            selected: style.board == i,
                            onTap: () => ctrl.setBoard(i),
                            child: RepaintBoundary(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: CustomPaint(
                                    painter: BoardPainter(layout, LudoStyle(board: i), true),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const _Heading(
                      'Customise board',
                      'Tweaks apply on top of the theme. "Theme" keeps its own look.',
                    ),
                    const SizedBox(height: 14),
                    _Group(
                      title: 'Path',
                      icon: Icons.route_rounded,
                      children: [
                        _OptionRow<CellShape>(
                          title: 'Cell shape',
                          values: CellShape.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.cell, CellShape.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.cell, v),
                        ),
                        _OptionRow<CellDepth>(
                          title: 'Cell depth',
                          values: CellDepth.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.depth, CellDepth.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.depth, v),
                        ),
                        _OptionRow<MarkStyle>(
                          title: 'Safe-cell marker',
                          values: MarkStyle.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.mark, MarkStyle.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.mark, v),
                        ),
                        _OptionRow<LaneStyle>(
                          title: 'Home lane',
                          values: LaneStyle.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.lane, LaneStyle.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.lane, v),
                        ),
                        _OptionRow<bool>(
                          title: 'Road under the path',
                          values: const [true, false],
                          labelOf: (v) => v ? 'On' : 'Off',
                          selected: switch (custom.values[CustomKey.ribbon]) {
                            1 => true,
                            0 => false,
                            _ => null,
                          },
                          onChanged: (v) =>
                              ctrl.setCustom(CustomKey.ribbon, v == null ? null : (v ? 1 : 0)),
                        ),
                        _SizeSlider(
                          value: custom.values[CustomKey.size] ?? (theme.cellScale * 100).round(),
                          isCustom: custom.values.containsKey(CustomKey.size),
                          onChanged: (v) => ctrl.setCustom(CustomKey.size, v),
                          onClear: () => ctrl.setCustom(CustomKey.size, null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Group(
                      title: 'Home yards',
                      icon: Icons.home_rounded,
                      children: [
                        _OptionRow<YardShape>(
                          title: 'Yard shape',
                          values: YardShape.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.yard, YardShape.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.yard, v),
                        ),
                        _OptionRow<SlotStyle>(
                          title: 'Token slots',
                          values: SlotStyle.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.slot, SlotStyle.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.slot, v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Group(
                      title: 'Main board',
                      icon: Icons.grid_view_rounded,
                      children: [
                        _OptionRow<SurfacePattern>(
                          title: 'Surface pattern',
                          values: SurfacePattern.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.pattern, SurfacePattern.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.pattern, v),
                        ),
                        _OptionRow<FrameStyle>(
                          title: 'Frame',
                          values: FrameStyle.values,
                          labelOf: (v) => v.label,
                          selected: custom.pick(CustomKey.frame, FrameStyle.values),
                          onChanged: (v) => ctrl.setCustomEnum(CustomKey.frame, v),
                        ),
                        _SwatchRow(
                          title: 'Board colour',
                          selected: custom.color(CustomKey.surface),
                          onChanged: (c) => ctrl.setCustomColor(CustomKey.surface, c),
                        ),
                        _SwatchRow(
                          title: 'Frame colour',
                          selected: custom.color(CustomKey.edge),
                          onChanged: (c) => ctrl.setCustomColor(CustomKey.edge, c),
                        ),
                        _SwatchRow(
                          title: 'Track colour',
                          selected: custom.color(CustomKey.track),
                          onChanged: (c) => ctrl.setCustomColor(CustomKey.track, c),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // _Group(
                    //   title: 'Dice',
                    //   icon: Icons.casino_rounded,
                    //   children: [
                    //     _OptionRow<PipShape>(
                    //       title: 'Pip shape',
                    //       values: PipShape.values,
                    //       labelOf: (v) => v.label,
                    //       selected: custom.pick(CustomKey.pip, PipShape.values),
                    //       onChanged: (v) => ctrl.setCustomEnum(CustomKey.pip, v),
                    //     ),
                    //   ],
                    // ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.customised});
  final bool customised;

  @override
  Widget build(BuildContext context) {
    final color = customised ? LudoPalette.accent : Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(customised ? Icons.tune_rounded : Icons.verified_rounded, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            customised ? 'Customised' : 'Theme',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 38,
          margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(
            color: LudoPalette.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900, fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A rounded card that groups related options under an icon header.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: LudoPalette.field.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _lavender.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _lavender),
              ),
              const SizedBox(width: 10),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: _lavender,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// A row of chips: "Theme" (= no override) followed by every value.
class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Theme', selected == null, () => onChanged(null)),
                for (final v in values) _chip(labelOf(v), selected == v, () => onChanged(v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: LudoPalette.accent,
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        side: BorderSide(color: isSelected ? LudoPalette.accent : Colors.white12),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          color: isSelected ? Colors.black : Colors.white,
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({required this.title, required this.selected, required this.onChanged});

  final String title;
  final Color? selected;
  final ValueChanged<Color?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _dot(
                  isSelected: selected == null,
                  onTap: () => onChanged(null),
                  fill: LudoPalette.field,
                  child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white70),
                ),
                for (final c in _swatches)
                  _dot(
                    isSelected: selected?.toARGB32() == c.toARGB32(),
                    onTap: () => onChanged(c),
                    fill: c,
                    child: selected?.toARGB32() == c.toARGB32()
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: c.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot({required bool isSelected, required VoidCallback onTap, required Color fill, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(
              color: isSelected ? LudoPalette.accent : Colors.white24,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [BoxShadow(color: LudoPalette.accent.withValues(alpha: 0.45), blurRadius: 10)]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SizeSlider extends StatelessWidget {
  const _SizeSlider({
    required this.value,
    required this.isCustom,
    required this.onChanged,
    required this.onClear,
  });

  final int value;
  final bool isCustom;
  final ValueChanged<int> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Cell size', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isCustom ? '$value%' : 'Theme ($value%)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (isCustom)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Back to theme size',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClear,
                ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: LudoPalette.accent,
              thumbColor: LudoPalette.accent,
              inactiveTrackColor: Colors.white12,
              trackHeight: 5,
              overlayColor: LudoPalette.accent.withValues(alpha: 0.2),
            ),
            child: Slider(
              min: 70,
              max: 100,
              divisions: 6,
              value: value.clamp(70, 100).toDouble(),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lays tiles out in equal-width columns that fill the whole row.
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final cols = ((c.maxWidth + gap) / (100 + gap)).floor().clamp(1, 8);
        final w = (c.maxWidth - gap * (cols - 1)) / cols - 0.01;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, required this.child});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              selected ? LudoPalette.accent.withValues(alpha: 0.18) : LudoPalette.field,
              LudoPalette.field,
            ],
          ),
          border: Border.all(
            color: selected ? LudoPalette.accent : Colors.white12,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: LudoPalette.accent.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: 1)]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                SizedBox(height: 68, child: Center(child: child)),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? LudoPalette.accent : Colors.white,
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: -14,
                right: -14,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: LudoPalette.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 14, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }
}