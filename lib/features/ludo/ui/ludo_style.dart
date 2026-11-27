import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/ludo_controller.dart';
import 'ludo_theme.dart';

// ---------------------------------------------------------------------------
// Building blocks of a board look. Every theme is a combination of these, and
// the player can override each one individually from the theme picker.
// ---------------------------------------------------------------------------

/// Shape of the cells on the shared track and the home lanes.
enum CellShape { rounded, square, circle, diamond, hexagon }

/// Shape of the four-token home yards.
enum YardShape { circle, rounded, octagon, hexagon, scallop }

/// Decorative texture drawn on the board surface.
enum SurfacePattern { none, grid, dots, checker, diagonal, wood, waves, stars }

/// Frame around the board.
enum FrameStyle { plain, double, studded, dashed, glow }

/// Icon drawn on safe cells and on every player's start cell.
enum MarkStyle { star, diamond, flower, ring, none }

/// Decoration on each player's private home lane.
enum LaneStyle { tinted, striped, arrows, dots }

/// How the track cells are lit.
enum CellDepth { flat, raised, inset }

/// Look of the four token slots inside a yard.
enum SlotStyle { ring, dimple, square, mark }

/// Look of the centre of the board.
enum HubStyle { wedges, gem, sun }

extension CellShapeName on CellShape {
  String get label => switch (this) {
        CellShape.rounded => 'Rounded',
        CellShape.square => 'Square',
        CellShape.circle => 'Circle',
        CellShape.diamond => 'Diamond',
        CellShape.hexagon => 'Hexagon',
      };
}

extension YardShapeName on YardShape {
  String get label => switch (this) {
        YardShape.circle => 'Circle',
        YardShape.rounded => 'Rounded',
        YardShape.octagon => 'Octagon',
        YardShape.hexagon => 'Hexagon',
        YardShape.scallop => 'Scallop',
      };
}

extension SurfacePatternName on SurfacePattern {
  String get label => switch (this) {
        SurfacePattern.none => 'Plain',
        SurfacePattern.grid => 'Grid',
        SurfacePattern.dots => 'Dots',
        SurfacePattern.checker => 'Checker',
        SurfacePattern.diagonal => 'Diagonal',
        SurfacePattern.wood => 'Wood',
        SurfacePattern.waves => 'Waves',
        SurfacePattern.stars => 'Stars',
      };
}

extension FrameStyleName on FrameStyle {
  String get label => switch (this) {
        FrameStyle.plain => 'Plain',
        FrameStyle.double => 'Double',
        FrameStyle.studded => 'Studded',
        FrameStyle.dashed => 'Stitched',
        FrameStyle.glow => 'Glow',
      };
}

extension MarkStyleName on MarkStyle {
  String get label => switch (this) {
        MarkStyle.star => 'Star',
        MarkStyle.diamond => 'Diamond',
        MarkStyle.flower => 'Flower',
        MarkStyle.ring => 'Ring',
        MarkStyle.none => 'None',
      };
}

extension LaneStyleName on LaneStyle {
  String get label => switch (this) {
        LaneStyle.tinted => 'Tinted',
        LaneStyle.striped => 'Striped',
        LaneStyle.arrows => 'Arrows',
        LaneStyle.dots => 'Dots',
      };
}

extension CellDepthName on CellDepth {
  String get label => switch (this) {
        CellDepth.flat => 'Flat',
        CellDepth.raised => 'Raised',
        CellDepth.inset => 'Inset',
      };
}

extension SlotStyleName on SlotStyle {
  String get label => switch (this) {
        SlotStyle.ring => 'Ring',
        SlotStyle.dimple => 'Dimple',
        SlotStyle.square => 'Square',
        SlotStyle.mark => 'Mark',
      };
}

/// Everything that makes one board look different from another: colours for
/// the surface, frame, track and yards, plus the shapes and textures used to
/// draw them. Seat colours stay the same in every style.
class BoardStyle {
  const BoardStyle({
    required this.name,
    required this.bg,
    required this.edge,
    required this.cellFill,
    required this.cellStroke,
    required this.yardInner,
    required this.inactive,
    required this.hubCenter,
    this.pattern = SurfacePattern.none,
    this.patternColor = const Color(0x1F000000),
    this.frame = FrameStyle.plain,
    this.cellShape = CellShape.rounded,
    this.cellDepth = CellDepth.flat,
    this.cellScale = 1.0,
    this.ribbon,
    this.yardShape = YardShape.circle,
    this.slot = SlotStyle.ring,
    this.mark = MarkStyle.star,
    this.markColor = const Color(0xFF8D8D8D),
    this.lane = LaneStyle.tinted,
    this.hub = HubStyle.wedges,
  });

  final String name;
  final List<Color> bg; // board surface gradient
  final List<Color> edge; // frame gradient
  final Color cellFill;
  final Color cellStroke;
  final Color yardInner;
  final Color inactive; // unused arms / yards
  final Color hubCenter;

  final SurfacePattern pattern;
  final Color patternColor;
  final FrameStyle frame;
  final CellShape cellShape;
  final CellDepth cellDepth;

  /// Cell size relative to the grid spacing (1.0 = default).
  final double cellScale;

  /// When set, a continuous road in this colour is drawn under the track.
  final Color? ribbon;
  final YardShape yardShape;
  final SlotStyle slot;
  final MarkStyle mark;
  final Color markColor; // colour of the marks on neutral safe cells
  final LaneStyle lane;
  final HubStyle hub;

  /// Returns this style with the player's [custom] choices applied on top.
  BoardStyle applyCustom(BoardCustom custom) {
    if (custom.isEmpty) return this;

    var bgColors = bg;
    var patternCol = patternColor;
    final surface = custom.color(CustomKey.surface);
    if (surface != null) {
      bgColors = [Color.lerp(surface, Colors.white, 0.18)!, Color.lerp(surface, Colors.black, 0.1)!];
      final light = surface.computeLuminance() > 0.45;
      patternCol = (light ? Colors.black : Colors.white).withValues(alpha: light ? 0.1 : 0.14);
    }

    var edgeColors = edge;
    final frameCol = custom.color(CustomKey.edge);
    if (frameCol != null) {
      edgeColors = [Color.lerp(frameCol, Colors.white, 0.22)!, Color.lerp(frameCol, Colors.black, 0.32)!];
    }

    var fill = cellFill;
    var stroke = cellStroke;
    var yard = yardInner;
    var hubC = hubCenter;
    final track = custom.color(CustomKey.track);
    if (track != null) {
      fill = track;
      yard = track;
      hubC = track;
      stroke = Color.lerp(track, Colors.black, 0.4)!;
    }

    final ribbonOverride = custom.values[CustomKey.ribbon];
    Color? ribbonColor = ribbon;
    if (ribbonOverride == 0) {
      ribbonColor = null;
    } else if (ribbonOverride == 1) {
      ribbonColor = ribbon ??
          Color.lerp(bgColors.last, bgColors.last.computeLuminance() > 0.45 ? Colors.black : Colors.white, 0.22);
    }

    final sizePct = custom.values[CustomKey.size];

    return BoardStyle(
      name: name,
      bg: bgColors,
      edge: edgeColors,
      cellFill: fill,
      cellStroke: stroke,
      yardInner: yard,
      inactive: inactive,
      hubCenter: hubC,
      pattern: custom.pick(CustomKey.pattern, SurfacePattern.values) ?? pattern,
      patternColor: patternCol,
      frame: custom.pick(CustomKey.frame, FrameStyle.values) ?? frame,
      cellShape: custom.pick(CustomKey.cell, CellShape.values) ?? cellShape,
      cellDepth: custom.pick(CustomKey.depth, CellDepth.values) ?? cellDepth,
      cellScale: sizePct == null ? cellScale : sizePct.clamp(70, 100) / 100,
      ribbon: ribbonColor,
      yardShape: custom.pick(CustomKey.yard, YardShape.values) ?? yardShape,
      slot: custom.pick(CustomKey.slot, SlotStyle.values) ?? slot,
      mark: custom.pick(CustomKey.mark, MarkStyle.values) ?? mark,
      markColor: markColor,
      lane: custom.pick(CustomKey.lane, LaneStyle.values) ?? lane,
      hub: hub,
    );
  }

  static const List<BoardStyle> all = [
    // Original four, now with a little extra texture.
    BoardStyle(
      name: 'Classic',
      bg: [Color(0xFFFFFBF0), Color(0xFFF6E7C1)],
      edge: [Color(0xFF8D6E63), Color(0xFF4E342E)],
      cellFill: Colors.white,
      cellStroke: Color(0xFF9E9E9E),
      yardInner: Color(0xFFFFFFFF),
      inactive: Color(0xFFBDBDBD),
      hubCenter: Colors.white,
    ),
    BoardStyle(
      name: 'Ocean',
      bg: [Color(0xFFE3F6FF), Color(0xFFB3E0F2)],
      edge: [Color(0xFF3D6E8C), Color(0xFF16405B)],
      cellFill: Color(0xFFF4FBFF),
      cellStroke: Color(0xFF7FA6BA),
      yardInner: Color(0xFFF4FBFF),
      inactive: Color(0xFFB6CBD6),
      hubCenter: Color(0xFFF4FBFF),
      pattern: SurfacePattern.waves,
      patternColor: Color(0x403D6E8C),
      frame: FrameStyle.double,
      cellDepth: CellDepth.raised,
      slot: SlotStyle.dimple,
      mark: MarkStyle.ring,
      markColor: Color(0xFF5B8FA8),
      hub: HubStyle.sun,
    ),
    BoardStyle(
      name: 'Forest',
      bg: [Color(0xFFE9F3DC), Color(0xFFC3DBA6)],
      edge: [Color(0xFF5D7A3A), Color(0xFF2E4620)],
      cellFill: Color(0xFFF8FBF1),
      cellStroke: Color(0xFF8AA06C),
      yardInner: Color(0xFFF8FBF1),
      inactive: Color(0xFFC3CCB3),
      hubCenter: Color(0xFFF8FBF1),
      pattern: SurfacePattern.dots,
      patternColor: Color(0x335D7A3A),
      cellShape: CellShape.circle,
      cellDepth: CellDepth.raised,
      ribbon: Color(0xFFC9A877),
      yardShape: YardShape.scallop,
      slot: SlotStyle.dimple,
      mark: MarkStyle.flower,
      markColor: Color(0xFF7C9A55),
      lane: LaneStyle.dots,
    ),
    BoardStyle(
      name: 'Midnight',
      bg: [Color(0xFF2B2B4A), Color(0xFF14142B)],
      edge: [Color(0xFFB39DDB), Color(0xFF5E4B9A)],
      cellFill: Color(0xFF3A3A60),
      cellStroke: Color(0xFF6C6C9A),
      yardInner: Color(0xFF3A3A60),
      inactive: Color(0xFF55557A),
      hubCenter: Color(0xFF3A3A60),
      pattern: SurfacePattern.grid,
      patternColor: Color(0x1FB39DDB),
      frame: FrameStyle.glow,
      markColor: Color(0xFFB39DDB),
      lane: LaneStyle.arrows,
      hub: HubStyle.gem,
    ),

    // New styles.
    BoardStyle(
      name: 'Wooden',
      bg: [Color(0xFFDDAE72), Color(0xFFBA8348)],
      edge: [Color(0xFF7A4B27), Color(0xFF3E2410)],
      cellFill: Color(0xFFF5E3C1),
      cellStroke: Color(0xFF8A5A2B),
      yardInner: Color(0xFFEFDBB2),
      inactive: Color(0xFFA98A62),
      hubCenter: Color(0xFFF5E3C1),
      pattern: SurfacePattern.wood,
      patternColor: Color(0x4D5B3A1A),
      frame: FrameStyle.studded,
      cellShape: CellShape.square,
      cellDepth: CellDepth.raised,
      yardShape: YardShape.rounded,
      slot: SlotStyle.dimple,
      markColor: Color(0xFF9A6A35),
      lane: LaneStyle.striped,
      hub: HubStyle.gem,
    ),
    BoardStyle(
      name: 'Candy',
      bg: [Color(0xFFFFE6F2), Color(0xFFFFC4DF)],
      edge: [Color(0xFFFF8FB5), Color(0xFFD81B60)],
      cellFill: Colors.white,
      cellStroke: Color(0xFFF48FB1),
      yardInner: Color(0xFFFFF6FA),
      inactive: Color(0xFFE8C5D6),
      hubCenter: Colors.white,
      pattern: SurfacePattern.dots,
      patternColor: Color(0x55FF80AB),
      frame: FrameStyle.dashed,
      cellShape: CellShape.circle,
      cellDepth: CellDepth.raised,
      yardShape: YardShape.scallop,
      slot: SlotStyle.dimple,
      mark: MarkStyle.flower,
      markColor: Color(0xFFF06292),
      lane: LaneStyle.dots,
      hub: HubStyle.gem,
    ),
    BoardStyle(
      name: 'Desert',
      bg: [Color(0xFFF7DEAC), Color(0xFFE3B878)],
      edge: [Color(0xFFB36B2E), Color(0xFF6B3A17)],
      cellFill: Color(0xFFFFF3D6),
      cellStroke: Color(0xFFB98A52),
      yardInner: Color(0xFFFFF3D6),
      inactive: Color(0xFFCDB68E),
      hubCenter: Color(0xFFFFF3D6),
      pattern: SurfacePattern.diagonal,
      patternColor: Color(0x2E8A5A2B),
      frame: FrameStyle.double,
      cellShape: CellShape.diamond,
      cellDepth: CellDepth.inset,
      yardShape: YardShape.hexagon,
      slot: SlotStyle.square,
      mark: MarkStyle.diamond,
      markColor: Color(0xFFB07A3A),
      lane: LaneStyle.arrows,
    ),
    BoardStyle(
      name: 'Neon',
      bg: [Color(0xFF10112B), Color(0xFF05050F)],
      edge: [Color(0xFF00E5FF), Color(0xFFD500F9)],
      cellFill: Color(0xFF181A3C),
      cellStroke: Color(0xFF00B8D4),
      yardInner: Color(0xFF14163A),
      inactive: Color(0xFF2B2E5A),
      hubCenter: Color(0xFF181A3C),
      pattern: SurfacePattern.grid,
      patternColor: Color(0x2400E5FF),
      frame: FrameStyle.glow,
      cellShape: CellShape.hexagon,
      yardShape: YardShape.hexagon,
      mark: MarkStyle.diamond,
      markColor: Color(0xFF00E5FF),
      lane: LaneStyle.arrows,
      hub: HubStyle.gem,
    ),
    BoardStyle(
      name: 'Frost',
      bg: [Color(0xFFF2FBFF), Color(0xFFCDEBFA)],
      edge: [Color(0xFF9BD0FA), Color(0xFF3F7FBF)],
      cellFill: Colors.white,
      cellStroke: Color(0xFF9CC7E4),
      yardInner: Colors.white,
      inactive: Color(0xFFC9DCE8),
      hubCenter: Colors.white,
      pattern: SurfacePattern.stars,
      patternColor: Color(0x805FA8E0),
      frame: FrameStyle.double,
      cellShape: CellShape.hexagon,
      cellDepth: CellDepth.raised,
      yardShape: YardShape.octagon,
      slot: SlotStyle.dimple,
      mark: MarkStyle.flower,
      markColor: Color(0xFF7FB8E6),
      lane: LaneStyle.striped,
      hub: HubStyle.sun,
    ),
    BoardStyle(
      name: 'Royal',
      bg: [Color(0xFF4F2D82), Color(0xFF2A1250)],
      edge: [Color(0xFFFFE082), Color(0xFF9E7A10)],
      cellFill: Color(0xFFEFE6FB),
      cellStroke: Color(0xFFB39DDB),
      yardInner: Color(0xFFEFE6FB),
      inactive: Color(0xFF7E6BA8),
      hubCenter: Color(0xFFFFF3C4),
      pattern: SurfacePattern.diagonal,
      patternColor: Color(0x1FFFD54F),
      frame: FrameStyle.studded,
      cellDepth: CellDepth.raised,
      yardShape: YardShape.octagon,
      slot: SlotStyle.mark,
      mark: MarkStyle.diamond,
      markColor: Color(0xFFD9A400),
      lane: LaneStyle.arrows,
      hub: HubStyle.gem,
    ),
    BoardStyle(
      name: 'Blueprint',
      bg: [Color(0xFF1F5099), Color(0xFF133468)],
      edge: [Color(0xFFBBDEFB), Color(0xFF64B5F6)],
      cellFill: Color(0xFF2A5CA8),
      cellStroke: Color(0xFFBBDEFB),
      yardInner: Color(0xFF245098),
      inactive: Color(0xFF3F6BAE),
      hubCenter: Color(0xFF2A5CA8),
      pattern: SurfacePattern.grid,
      patternColor: Color(0x24FFFFFF),
      frame: FrameStyle.dashed,
      cellShape: CellShape.square,
      yardShape: YardShape.rounded,
      slot: SlotStyle.square,
      mark: MarkStyle.ring,
      markColor: Color(0xFFBBDEFB),
      lane: LaneStyle.dots,
    ),
    BoardStyle(
      name: 'Galaxy',
      bg: [Color(0xFF2A1B5E), Color(0xFF0B0724)],
      edge: [Color(0xFF7C4DFF), Color(0xFF00BCD4)],
      cellFill: Color(0xFF2E2766),
      cellStroke: Color(0xFF7B6FD6),
      yardInner: Color(0xFF241E52),
      inactive: Color(0xFF433B85),
      hubCenter: Color(0xFF2E2766),
      pattern: SurfacePattern.stars,
      patternColor: Color(0xB3FFFFFF),
      frame: FrameStyle.glow,
      cellShape: CellShape.circle,
      ribbon: Color(0xFF3B2F85),
      yardShape: YardShape.scallop,
      slot: SlotStyle.dimple,
      markColor: Color(0xFFFFE082),
      lane: LaneStyle.dots,
      hub: HubStyle.sun,
    ),
    BoardStyle(
      name: 'Lava',
      bg: [Color(0xFF3F1C14), Color(0xFF1A0A08)],
      edge: [Color(0xFFFF7043), Color(0xFF8E2A0C)],
      cellFill: Color(0xFF4F2D24),
      cellStroke: Color(0xFFB5522F),
      yardInner: Color(0xFF3A201A),
      inactive: Color(0xFF5E3A30),
      hubCenter: Color(0xFF4F2D24),
      pattern: SurfacePattern.diagonal,
      patternColor: Color(0x33FF7043),
      frame: FrameStyle.studded,
      cellShape: CellShape.diamond,
      cellDepth: CellDepth.raised,
      yardShape: YardShape.hexagon,
      slot: SlotStyle.dimple,
      mark: MarkStyle.diamond,
      markColor: Color(0xFFFFAB40),
      lane: LaneStyle.striped,
      hub: HubStyle.gem,
    ),
    BoardStyle(
      name: 'Arcade',
      bg: [Color(0xFF273563), Color(0xFF1B2547)],
      edge: [Color(0xFFFFEE58), Color(0xFFFF9800)],
      cellFill: Color(0xFFFFFDE7),
      cellStroke: Color(0xFF2B2B3F),
      yardInner: Color(0xFFFFFDE7),
      inactive: Color(0xFF4A557F),
      hubCenter: Color(0xFFFFFDE7),
      pattern: SurfacePattern.checker,
      patternColor: Color(0x14FFFFFF),
      frame: FrameStyle.dashed,
      cellShape: CellShape.square,
      yardShape: YardShape.rounded,
      slot: SlotStyle.square,
      markColor: Color(0xFFFF9800),
      lane: LaneStyle.arrows,
    ),
  ];
}

enum TokenStyle { ball, pawn, gem, ring }

extension TokenStyleName on TokenStyle {
  String get label => switch (this) {
        TokenStyle.ball => 'Ball',
        TokenStyle.pawn => 'Pawn',
        TokenStyle.gem => 'Gem',
        TokenStyle.ring => 'Ring',
      };
}

/// Look of the dice. Append new values at the end: the index is saved.
enum DiceStyle { classic, player, neon, wood, gold, ice, candy, arcade, royal }

extension DiceStyleName on DiceStyle {
  String get label => switch (this) {
        DiceStyle.classic => 'Classic',
        DiceStyle.player => 'Player',
        DiceStyle.neon => 'Neon',
        DiceStyle.wood => 'Wooden',
        DiceStyle.gold => 'Gold',
        DiceStyle.ice => 'Ice',
        DiceStyle.candy => 'Candy',
        DiceStyle.arcade => 'Pixel',
        DiceStyle.royal => 'Royal',
      };
}

/// Shape of the pips (dots) on the dice faces.
enum PipShape { round, square, diamond, star }

extension PipShapeName on PipShape {
  String get label => switch (this) {
        PipShape.round => 'Round',
        PipShape.square => 'Square',
        PipShape.diamond => 'Diamond',
        PipShape.star => 'Star',
      };
}

/// Everything that makes one die look different from another. Rendered by
/// `DiceFace` (dice_widget.dart).
@immutable
class DiceSkin {
  const DiceSkin({
    required this.body,
    this.pip,
    this.edge,
    this.pipShape = PipShape.round,
    this.radius = 0.2,
    this.borderWidth = 3,
    this.fromAccent = false,
    this.glowPips = false,
    this.engraved = false,
    this.grain = false,
    this.shine = false,
  });

  /// Two-colour body gradient (top-left to bottom-right).
  final List<Color> body;

  /// Pip colour. Null = the current player's colour when the die is active.
  final Color? pip;

  /// Border colour. Null = the current player's colour when the die is active.
  final Color? edge;
  final PipShape pipShape;

  /// Corner radius as a fraction of the die size.
  final double radius;
  final double borderWidth;

  /// Body is tinted with the current player's colour instead of [body].
  final bool fromAccent;

  /// Pips emit a soft glow.
  final bool glowPips;

  /// Pips look carved into the body.
  final bool engraved;

  /// Faint wood grain across the body.
  final bool grain;

  /// Glossy highlight across the top-left.
  final bool shine;

  /// This skin with the player's own [shape] applied (null = keep the skin's).
  DiceSkin withPip(PipShape? shape) {
    if (shape == null || shape == pipShape) return this;
    return DiceSkin(
      body: body,
      pip: pip,
      edge: edge,
      pipShape: shape,
      radius: radius,
      borderWidth: borderWidth,
      fromAccent: fromAccent,
      glowPips: glowPips,
      engraved: engraved,
      grain: grain,
      shine: shine,
    );
  }

  static const DiceSkin classic = DiceSkin(body: [Colors.white, Color(0xFFE3E0F3)]);

  // Same order as [DiceStyle].
  static const List<DiceSkin> _all = [
    classic,
    DiceSkin(
      body: [Colors.white, Colors.white],
      pip: Colors.white,
      edge: Colors.white,
      radius: 0.22,
      fromAccent: true,
      shine: true,
    ),
    DiceSkin(
      body: [Color(0xFF181A3C), Color(0xFF05050F)],
      pip: Color(0xFF00E5FF),
      edge: Color(0xFF00E5FF),
      radius: 0.16,
      glowPips: true,
    ),
    DiceSkin(
      body: [Color(0xFFE6BC80), Color(0xFFB98443)],
      pip: Color(0xFF3E2410),
      edge: Color(0xFF7A4B27),
      radius: 0.14,
      engraved: true,
      grain: true,
    ),
    DiceSkin(
      body: [Color(0xFFFFE680), Color(0xFFE0A100)],
      pip: Color(0xFF5D3A00),
      edge: Color(0xFFFFF3C4),
      engraved: true,
      shine: true,
    ),
    DiceSkin(
      body: [Color(0xFFF2FBFF), Color(0xFFA8D8F2)],
      pip: Color(0xFF1E6FA8),
      edge: Color(0xFFBFE6FA),
      radius: 0.26,
      shine: true,
    ),
    DiceSkin(
      body: [Color(0xFFFFC1DC), Color(0xFFFF80AB)],
      pip: Colors.white,
      edge: Colors.white,
      radius: 0.32,
      shine: true,
    ),
    DiceSkin(
      body: [Color(0xFF2B2B3F), Color(0xFF1B1B2B)],
      pip: Color(0xFFFFEE58),
      edge: Color(0xFFFF9800),
      pipShape: PipShape.square,
      radius: 0.06,
      borderWidth: 4,
    ),
    DiceSkin(
      body: [Color(0xFF6A3FB5), Color(0xFF2A1250)],
      pip: Color(0xFFFFE082),
      edge: Color(0xFFFFE082),
      pipShape: PipShape.diamond,
      radius: 0.18,
      shine: true,
    ),
  ];

  static DiceSkin of(DiceStyle style) => _all[style.index.clamp(0, _all.length - 1)];
}

/// Keys of the individual overrides stored in a [BoardCustom].
class CustomKey {
  CustomKey._();
  static const cell = 'cell';
  static const yard = 'yard';
  static const pattern = 'pattern';
  static const mark = 'mark';
  static const frame = 'frame';
  static const lane = 'lane';
  static const depth = 'depth';
  static const slot = 'slot';
  static const ribbon = 'ribbon'; // 0 = off, 1 = on
  static const size = 'size'; // percent, 70..100
  static const surface = 'surface'; // ARGB colour
  static const edge = 'edge'; // ARGB colour
  static const track = 'track'; // ARGB colour
  static const pip = 'pip'; // PipShape index (dice)
}

/// The player's own tweaks on top of the chosen board theme. A missing key
/// means "use whatever the theme says".
@immutable
class BoardCustom {
  const BoardCustom([this.values = const {}]);

  final Map<String, int> values;

  bool get isEmpty => values.isEmpty;

  /// The enum value stored under [key], or null when the theme default applies.
  T? pick<T extends Enum>(String key, List<T> all) {
    final i = values[key];
    if (i == null || i < 0 || i >= all.length) return null;
    return all[i];
  }

  Color? color(String key) {
    final v = values[key];
    return v == null ? null : Color(v);
  }

  /// Returns a copy with [key] set to [value] (or cleared when null).
  BoardCustom set(String key, int? value) {
    final m = Map<String, int>.of(values);
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    return BoardCustom(Map.unmodifiable(m));
  }

  BoardCustom setEnum(String key, Enum? value) => set(key, value?.index);

  BoardCustom setColor(String key, Color? value) => set(key, value?.toARGB32());

  @override
  bool operator ==(Object other) => other is BoardCustom && mapEquals(values, other.values);

  @override
  int get hashCode => Object.hashAllUnordered(values.entries.map((e) => Object.hash(e.key, e.value)));
}

class LudoStyle {
  const LudoStyle({
    this.board = 0,
    this.token = TokenStyle.ball,
    this.dice = DiceStyle.classic,
    this.custom = const BoardCustom(),
  });
  final int board;
  final TokenStyle token;
  final DiceStyle dice;
  final BoardCustom custom;

  /// The chosen theme with the player's overrides applied.
  BoardStyle get boardStyle =>
      BoardStyle.all[board.clamp(0, BoardStyle.all.length - 1)].applyCustom(custom);

  /// The chosen dice with the player's pip-shape override applied.
  DiceSkin get diceSkin => DiceSkin.of(dice).withPip(custom.pick(CustomKey.pip, PipShape.values));

  LudoStyle copyWith({int? board, TokenStyle? token, DiceStyle? dice, BoardCustom? custom}) => LudoStyle(
        board: board ?? this.board,
        token: token ?? this.token,
        dice: dice ?? this.dice,
        custom: custom ?? this.custom,
      );

  @override
  bool operator ==(Object other) =>
      other is LudoStyle &&
      other.board == board &&
      other.token == token &&
      other.dice == dice &&
      other.custom == custom;

  @override
  int get hashCode => Object.hash(board, token, dice, custom);
}

/// The player's chosen board / token / dice look, remembered between launches.
class StyleController extends Notifier<LudoStyle> {
  @override
  LudoStyle build() {
    _load();
    return const LudoStyle();
  }

  Future<void> _load() async {
    final store = ref.read(ludoStoreProvider);
    final (b, t) = await store.loadStyle();
    final custom = await store.loadBoardCustom();
    final d = await store.loadDiceStyle();
    state = LudoStyle(
      board: b.clamp(0, BoardStyle.all.length - 1),
      token: TokenStyle.values[t.clamp(0, TokenStyle.values.length - 1)],
      dice: DiceStyle.values[d.clamp(0, DiceStyle.values.length - 1)],
      custom: BoardCustom(Map.unmodifiable(custom)),
    );
  }

  void _save() {
    final store = ref.read(ludoStoreProvider);
    store.saveStyle(state.board, state.token.index);
    store.saveDiceStyle(state.dice.index);
    store.saveBoardCustom(state.custom.values);
  }

  void setBoard(int i) {
    state = state.copyWith(board: i);
    _save();
  }

  void setToken(TokenStyle t) {
    state = state.copyWith(token: t);
    _save();
  }

  void setDice(DiceStyle d) {
    state = state.copyWith(dice: d);
    _save();
  }

  /// Sets or clears (null) one customisation.
  void setCustom(String key, int? value) {
    state = state.copyWith(custom: state.custom.set(key, value));
    _save();
  }

  void setCustomEnum(String key, Enum? value) => setCustom(key, value?.index);

  void setCustomColor(String key, Color? value) => setCustom(key, value?.toARGB32());

  /// Drops every override and goes back to the pure theme.
  void resetCustom() {
    state = state.copyWith(custom: const BoardCustom());
    _save();
  }

  /// Picks a random theme and a few random tweaks.
  void shuffle(int seed) {
    final r = _Lcg(seed);
    var c = const BoardCustom();
    if (r.next(3) == 0) c = c.setEnum(CustomKey.cell, CellShape.values[r.next(CellShape.values.length)]);
    if (r.next(3) == 0) c = c.setEnum(CustomKey.yard, YardShape.values[r.next(YardShape.values.length)]);
    if (r.next(3) == 0) c = c.setEnum(CustomKey.pattern, SurfacePattern.values[r.next(SurfacePattern.values.length)]);
    if (r.next(3) == 0) c = c.setEnum(CustomKey.mark, MarkStyle.values[r.next(MarkStyle.values.length)]);
    state = state.copyWith(
      board: r.next(BoardStyle.all.length),
      dice: DiceStyle.values[r.next(DiceStyle.values.length)],
      custom: c,
    );
    _save();
  }
}

/// Tiny deterministic generator so [StyleController.shuffle] needs no dart:math.
class _Lcg {
  _Lcg(int seed) : _s = (seed ^ 0x5DEECE66D) & 0x7FFFFFFF;
  int _s;
  int next(int n) {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return (_s >> 8) % n;
  }
}

final ludoStyleProvider = NotifierProvider<StyleController, LudoStyle>(StyleController.new);
