import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours used by the Ludo screens. Seat colours are assigned automatically
/// from the arm a seat sits on, so a given layout always looks the same.
class LudoPalette {
  LudoPalette._();

  static const List<Color> seatColors = [
    Color(0xFFE53935), // red
    Color(0xFF43A047), // green
    Color(0xFFFBC02D), // yellow
    Color(0xFF1E88E5), // blue
    Color(0xFFF57C00), // orange
    Color(0xFF8E24AA), // purple
  ];

  static const List<String> colorNames = [
    'Red',
    'Green',
    'Yellow',
    'Blue',
    'Orange',
    'Purple',
  ];

  static const Color boardBg = Color(0xFFFFF8E7);
  static const Color boardEdge = Color(0xFF5D4037);
  static const Color cellFill = Colors.white;
  static const Color cellStroke = Color(0xFF9E9E9E);
  static const Color inactive = Color(0xFFBDBDBD);
  static const Color gold = Color(0xFFFFC107);

  // Screen background gradient.
  static const Color bgTop = Color(0xFF0A0920);
  static const Color bgMid = Color(0xFF17123A);
  static const Color bgBottom = Color(0xFF2A1650);
  static const Color panel = Color(0xFF1E1A3F);
  static const Color field = Color(0xFF2B2658);
  static const Color accent = Color(0xFFFFB300);

  /// Accent colours that mark teams on the board (kept apart from seat colours).
  static const List<Color> teamColors = [
    Color(0xFFFFFFFF), // team 1: white
    Color(0xFFFFC107), // team 2: gold
    Color(0xFFB0B0B0), // team 3: silver
  ];
  static const List<String> teamNames = ['A', 'B', 'C'];
  static String teamName(int team) => teamNames[team % teamNames.length];

  static Color team(int team) => teamColors[team % teamColors.length];

  static Color seat(int colorIndex) => seatColors[colorIndex % seatColors.length];
  static String name(int colorIndex) => colorNames[colorIndex % colorNames.length];

  static Color tint(Color c, [double t = 0.55]) => Color.lerp(c, Colors.white, t)!;
  static Color shade(Color c, [double t = 0.3]) => Color.lerp(c, Colors.black, t)!;
}

/// Full-screen purple gradient with soft, slowly decorative circles.
class LudoBackground extends StatelessWidget {
  const LudoBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LudoPalette.bgTop, LudoPalette.bgMid, LudoPalette.bgBottom],
        ),
      ),
      child: CustomPaint(
        painter: _BubblesPainter(),
        child: child,
      ),
    );
  }
}

class _BubblesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = LudoPalette.seatColors;
    final r = math.Random(7);
    for (var i = 0; i < 14; i++) {
      final c = colors[i % colors.length].withValues(alpha: 0.07 + 0.05 * r.nextDouble());
      final radius = size.shortestSide * (0.05 + 0.13 * r.nextDouble());
      canvas.drawCircle(
        Offset(size.width * r.nextDouble(), size.height * r.nextDouble()),
        radius,
        Paint()..color = c,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Scaffold with the Ludo gradient and a transparent, white app bar.
class LudoScaffold extends StatelessWidget {
  const LudoScaffold({
    super.key,
    this.title,
    this.actions,
    required this.body,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget body;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: LudoTheme.dark(),
      child: LudoBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: title == null && actions == null
            ? null
            : AppBar(
                title: title,
                actions: actions,
                centerTitle: true,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: automaticallyImplyLeading,
                titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
        body: body,
      ),
      ),
    );
  }
}

/// Rounded dark panel used for grouped content on the gradient background.
class LudoPanel extends StatelessWidget {
  const LudoPanel({super.key, this.title, this.icon, this.trailing, required this.child, this.padding});
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LudoPalette.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: const Color(0xFFB39DDB)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Optional theme for stand-alone use of the module. When the module is
/// embedded in an existing app, keep the app's own Theme instead.
class LudoTheme {
  LudoTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: Brightness.dark,
    ).copyWith(
      surface: LudoPalette.panel,
      surfaceContainerHighest: LudoPalette.field,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: LudoPalette.bgTop,
      cardTheme: CardThemeData(
        color: LudoPalette.panel,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: LudoPalette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LudoPalette.field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LudoPalette.bgMid,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF3F0FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Large gradient button used on the home and online menu screens.
class LudoModeButton extends StatelessWidget {
  const LudoModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        height: 130,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      child: Icon(icon, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

