import 'dart:math' as math;

/// A point in board space. One unit == one track cell. The board centre is
/// (0, 0), +x points right and +y points down (screen coordinates).
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator *(double k) => Pt(x * k, y * k);

  double distanceTo(Pt o) {
    final dx = x - o.x;
    final dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  String toString() => 'Pt($x, $y)';
}

/// A named way of splitting the seats of a layout into teams.
/// [teamOfSeat] maps seat index -> team id.
class TeamPreset {
  final String label;
  final List<int> teamOfSeat;
  const TeamPreset(this.label, this.teamOfSeat);
}

/// Geometry + path description of one board.
///
/// A board is made of [arms] identical "spokes" arranged clockwise around the
/// centre, starting with arm 0 pointing up. Every arm is three cells wide and
/// [armLength] cells long, exactly like the arms of the classic cross board.
///
/// The shared track ("ring") runs clockwise: for every arm it goes OUT along
/// the left column, across the tip cell, then back IN along the right column,
/// optionally followed by [cornerCells] connector cells that bridge the gap to
/// the next arm. A player's private home lane is the middle column of their
/// own arm (the final [laneLength] cells before the centre).
///
/// Token progress is a single integer:
///   -1                        in the home yard
///   0 .. ringSteps-1          on the shared ring (0 = own start cell)
///   ringSteps .. finish-1     on the private home lane
///   finishProgress            finished (centre of the board)
///
/// Every seat walks the same number of steps, so paths are balanced by
/// rotational symmetry no matter how many players are seated.
class BoardLayout {
  final int playerCount;
  final String name;
  final String description;
  final int arms;
  final int armLength;
  final int cornerCells;
  final double innerRadius;

  /// Arm index (clockwise, 0 = top) used by each seat.
  final List<int> seatArms;

  /// Cells (counted from every arm's start cell) that are extra safe "stars".
  final List<int> starOffsets;

  final double yardDistance;
  final double yardRadius;
  final List<TeamPreset> teamPresets;

  late final int segmentLength;
  late final int ringLength;
  late final int laneLength;
  late final int ringSteps;
  late final int finishProgress;
  late final double hubRadius;
  late final double extent;
  late final List<Pt> ringPoints;
  late final List<double> ringAngles;
  late final List<List<Pt>> lanePoints;
  late final Set<int> startCells;
  late final Set<int> starCells;
  late final Set<int> safeCells;

  BoardLayout._({
    required this.playerCount,
    required this.name,
    required this.description,
    required this.arms,
    required this.armLength,
    required this.cornerCells,
    required this.innerRadius,
    required this.seatArms,
    required this.starOffsets,
    required this.yardDistance,
    required this.yardRadius,
    required this.teamPresets,
  }) {
    _build();
  }

  static final Map<int, BoardLayout> _cache = {};

  /// Returns the dedicated layout for [players] (2..6).
  static BoardLayout forPlayers(int players) {
    if (players < 2 || players > 6) {
      throw ArgumentError.value(players, 'players', 'Ludo supports 2 to 6 players');
    }
    return _cache.putIfAbsent(players, () => _create(players));
  }

  static BoardLayout _create(int players) {
    switch (players) {
      case 2:
        // The classic cross, players seated on opposite arms; the other two
        // arms stay on the track as neutral stretches.
        return BoardLayout._(
          playerCount: 2,
          name: 'Classic cross',
          description: 'Classic 4-arm cross, 2 players on opposite arms',
          arms: 4,
          armLength: 6,
          cornerCells: 0,
          innerRadius: 2,
          seatArms: const [0, 2],
          starOffsets: const [8],
          yardDistance: 5.6,
          yardRadius: 2.3,
          teamPresets: const [],
        );
      case 3:
        // The classic cross with one arm left empty.
        return BoardLayout._(
          playerCount: 3,
          name: 'Classic cross',
          description: 'Classic 4-arm cross, 3 players, one arm left empty',
          arms: 4,
          armLength: 6,
          cornerCells: 0,
          innerRadius: 2,
          seatArms: const [0, 1, 2],
          starOffsets: const [8],
          yardDistance: 5.6,
          yardRadius: 2.3,
          teamPresets: const [],
        );
      case 4:
        return BoardLayout._(
          playerCount: 4,
          name: 'Classic cross',
          description: 'Traditional 4-arm cross board',
          arms: 4,
          armLength: 6,
          cornerCells: 0,
          innerRadius: 2,
          seatArms: const [0, 1, 2, 3],
          starOffsets: const [8],
          yardDistance: 5.6,
          yardRadius: 2.3,
          teamPresets: const [
            TeamPreset('2 vs 2 (partners sit opposite)', [0, 1, 0, 1]),
          ],
        );
      case 5:
        return BoardLayout._(
          playerCount: 5,
          name: 'Pentagon star',
          description: '5-arm star board',
          arms: 5,
          armLength: 6, // home lane = armLength - 1 = 5 cells
          cornerCells: 0,
          innerRadius: 2.5,
          seatArms: const [0, 1, 2, 3, 4],
          starOffsets: const [8],
          yardDistance: 6.8,
          yardRadius: 2.1,
          teamPresets: const [],
        );
      default:
        return BoardLayout._(
          playerCount: 6,
          name: 'Hexagon star',
          description: '6-arm star board',
          arms: 6,
          armLength: 6, // home lane = armLength - 1 = 5 cells
          cornerCells: 0,
          innerRadius: 3,
          seatArms: const [0, 1, 2, 3, 4, 5],
          starOffsets: const [8],
          yardDistance: 7.75,
          yardRadius: 2.0,
          teamPresets: const [
            TeamPreset('3 teams of 2 (partners sit opposite)', [0, 1, 2, 0, 1, 2]),
            TeamPreset('2 teams of 3 (alternate seats)', [0, 1, 0, 1, 0, 1]),
          ],
        );
    }
  }

  // ---------------------------------------------------------------- geometry

  /// Clockwise angle (radians, 0 = up) of arm [k].
  double armAngle(int k) => 2 * math.pi * k / arms;

  /// Arm-local (u across, v outward) -> world coordinates.
  Pt _world(int arm, double u, double v) {
    final th = armAngle(arm);
    final dx = math.sin(th);
    final dy = -math.cos(th);
    final rx = math.cos(th);
    final ry = math.sin(th);
    return Pt(dx * v + rx * u, dy * v + ry * u);
  }

  void _build() {
    segmentLength = 2 * armLength + 1 + cornerCells;
    ringLength = arms * segmentLength;
    laneLength = armLength - 1;
    ringSteps = ringLength - 1;
    finishProgress = ringSteps + laneLength;
    hubRadius = innerRadius - 0.5;

    final tipV = innerRadius + armLength - 1;
    final pts = <Pt>[];
    final angs = <double>[];
    for (var k = 0; k < arms; k++) {
      final th = armAngle(k);
      for (var j = 0; j < armLength; j++) {
        pts.add(_world(k, -1, innerRadius + j));
        angs.add(th);
      }
      pts.add(_world(k, 0, tipV));
      angs.add(th);
      for (var j = 0; j < armLength; j++) {
        pts.add(_world(k, 1, tipV - j));
        angs.add(th);
      }
      if (cornerCells > 0) {
        final last = pts.last;
        final next = _world((k + 1) % arms, -1, innerRadius);
        for (var c = 1; c <= cornerCells; c++) {
          final t = c / (cornerCells + 1);
          pts.add(Pt(last.x + (next.x - last.x) * t, last.y + (next.y - last.y) * t));
          angs.add(th + math.pi / arms);
        }
      }
    }
    ringPoints = List.unmodifiable(pts);
    ringAngles = List.unmodifiable(angs);

    lanePoints = List.unmodifiable([
      for (var k = 0; k < arms; k++)
        List<Pt>.unmodifiable([
          for (var i = 0; i < laneLength; i++) _world(k, 0, tipV - 1 - i),
        ]),
    ]);

    final starts = <int>{};
    final stars = <int>{};
    for (var k = 0; k < arms; k++) {
      final s = startCell(k);
      starts.add(s);
      for (final off in starOffsets) {
        stars.add((s + off) % ringLength);
      }
    }
    startCells = Set.unmodifiable(starts);
    starCells = Set.unmodifiable(stars);
    safeCells = Set.unmodifiable({...starts, ...stars});

    var maxAbs = 0.0;
    void grow(double a) {
      if (a.abs() > maxAbs) maxAbs = a.abs();
    }

    for (final p in pts) {
      grow(p.x + 0.5);
      grow(p.y + 0.5);
      grow(p.x - 0.5);
      grow(p.y - 0.5);
    }
    for (var k = 0; k < arms; k++) {
      final c = yardCenter(k);
      grow(c.x + yardRadius);
      grow(c.x - yardRadius);
      grow(c.y + yardRadius);
      grow(c.y - yardRadius);
    }
    extent = maxAbs + 0.45;
  }

  // ------------------------------------------------------------------- paths

  /// Ring index of the start cell of [arm].
  int startCell(int arm) => arm * segmentLength + armLength + 2;

  /// Ring index of the tip cell of [arm] (where that arm's home lane begins).
  int tipCell(int arm) => arm * segmentLength + armLength;

  /// Ring index occupied by a token of [seat] at ring [progress]
  /// (0 <= progress < ringSteps).
  int ringCell(int seat, int progress) =>
      (startCell(seatArms[seat]) + progress) % ringLength;

  bool isSafeCell(int ringIndex) => safeCells.contains(ringIndex);

  // ---------------------------------------------------------------- yards etc

  Pt yardCenter(int arm) {
    final a = armAngle(arm) + math.pi / arms;
    return Pt(math.sin(a) * yardDistance, -math.cos(a) * yardDistance);
  }

  Pt yardSlot(int arm, int i) {
    final c = yardCenter(arm);
    final s = yardRadius * 0.34;
    return Pt(c.x + (i % 2 == 0 ? -s : s), c.y + (i < 2 ? -s : s));
  }

  Pt finishSlot(int arm, int i) {
    final th = armAngle(arm);
    final dx = math.sin(th);
    final dy = -math.cos(th);
    final rx = math.cos(th);
    final ry = math.sin(th);
    final base = hubRadius * 0.55;
    final a = (i % 2 == 0 ? -1 : 1) * 0.26;
    final b = (i < 2 ? -1 : 1) * 0.26;
    return Pt(dx * (base + b) + rx * a, dy * (base + b) + ry * a);
  }

  /// Where a token of [seat] with the given [progress] is drawn.
  Pt tokenPoint(int seat, int index, int progress) {
    final arm = seatArms[seat];
    if (progress < 0) return yardSlot(arm, index);
    if (progress >= finishProgress) return finishSlot(arm, index);
    if (progress < ringSteps) return ringPoints[ringCell(seat, progress)];
    return lanePoints[arm][progress - ringSteps];
  }

  /// Colour slot (0..5) used by [seat]; derived from its arm.
  int colorIndexOfSeat(int seat) => seatArms[seat];
}
