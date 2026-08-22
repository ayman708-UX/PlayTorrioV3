import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/dock_theme_settings.dart';

/// Shared decoration helpers for dock/menu theming.
abstract final class DockThemeStyles {
  static BoxDecoration dockShellDecoration(DockTheme theme) {
    return switch (theme) {
      DockTheme.standard => BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x30FFFFFF), Color(0x14FFFFFF)],
          ),
          border: Border.all(color: const Color(0x26FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
      DockTheme.liquidGlass => BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
      DockTheme.carbonFiber => BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: const Color(0xFF101010),
          border: Border.all(color: const Color(0xFF5A5A5A), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: Color(0x33FFFFFF),
              blurRadius: 0,
              offset: Offset(0, -1),
            ),
          ],
        ),
      DockTheme.retro90s => BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF00FF),
              Color(0xFF00FFFF),
              Color(0xFFFFFF00),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF000000),
              blurRadius: 0,
              offset: Offset(6, 6),
            ),
          ],
        ),
    };
  }

  static BoxDecoration dockInnerDecoration(DockTheme theme) {
    return switch (theme) {
      DockTheme.retro90s => BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF120018),
          border: Border.all(color: Colors.black, width: 3),
        ),
      DockTheme.carbonFiber => BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF0A0A0A),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
      _ => const BoxDecoration(),
    };
  }

  static BoxDecoration dockItemDecoration(
    DockTheme theme, {
    required bool hovered,
    required bool pressed,
  }) {
    return switch (theme) {
      DockTheme.carbonFiber => BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hovered
                ? const [Color(0xFF3A3A3A), Color(0xFF1E1E1E)]
                : const [Color(0xFF242424), Color(0xFF121212)],
          ),
          border: Border.all(
            color: hovered ? const Color(0xFF8A8A8A) : const Color(0xFF404040),
          ),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
      DockTheme.retro90s => BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: pressed
              ? const Color(0xFFFF00AA)
              : (hovered ? const Color(0xFF00E5FF) : const Color(0xFF2E0050)),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: pressed ? 0.2 : 0.85),
              offset: pressed ? const Offset(2, 2) : const Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        ),
      _ => BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hovered
                ? const [Color(0x38FFFFFF), Color(0x1FFFFFFF)]
                : const [Color(0x24FFFFFF), Color(0x12FFFFFF)],
          ),
          border: Border.all(color: const Color(0x26FFFFFF)),
        ),
    };
  }

  static Color dockIconColor(DockTheme theme, {required bool hovered}) {
    return switch (theme) {
      DockTheme.carbonFiber =>
        hovered ? const Color(0xFFF0F0F0) : const Color(0xFFB8B8B8),
      DockTheme.retro90s =>
        hovered ? Colors.black : const Color(0xFFFFFF00),
      _ => const Color(0xF2FFFFFF),
    };
  }

  static List<BoxShadow> dockOuterShadow(DockTheme theme) {
    if (theme == DockTheme.liquidGlass) {
      return const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ];
    }
    return const [];
  }
}

/// Carbon weave overlay for the carbon fiber menu theme.
class CarbonFiberPattern extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const CarbonFiberPattern({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: CustomPaint(
              painter: _CarbonFiberPainter(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarbonFiberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final dark = Paint()..color = const Color(0xFF080808);
    final light = Paint()..color = const Color(0xFF1E1E1E);

    for (double y = -size.height; y < size.height * 2; y += cell) {
      for (double x = -size.width; x < size.width * 2; x += cell) {
        final path = Path()
          ..moveTo(x, y)
          ..lineTo(x + cell, y + cell)
          ..lineTo(x, y + cell * 2)
          ..lineTo(x - cell, y + cell)
          ..close();
        canvas.drawPath(path, ((x + y) / cell).floor().isEven ? dark : light);
      }
    }

    final gloss = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.03),
        ],
        stops: const [0, 0.45, 1],
        transform: GradientRotation(math.pi / 4),
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, gloss);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
