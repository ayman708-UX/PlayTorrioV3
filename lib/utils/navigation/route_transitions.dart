import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Standard Material-style push transition helper.
Route<T> materialRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) =>
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      settings: settings,
    );

/// A premium, liquid-like circular reveal transition. 
/// The new screen expands like a drop of liquid from the exact point the user tapped,
/// while the old screen scales back slightly into the distance.
class LiquidRevealRoute extends PageRouteBuilder {
  final Widget page;
  final Offset? tapPosition;

  LiquidRevealRoute({
    required this.page,
    this.tapPosition,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 750), // Slower for that fluid, majestic feel
          reverseTransitionDuration: const Duration(milliseconds: 650),
          opaque: true, // During transition it will still show the previous route, but stops rendering it when finished!
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // A highly organic, fluid curve (starts fast, very long smooth tail)
            final curve = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.2, 1.0, 0.2, 1.0),
              reverseCurve: Curves.easeInCirc,
            );

            return AnimatedBuilder(
              animation: curve,
              builder: (context, childWidget) {
                // Determine the center of the reveal (default to bottom center if null)
                final center = tapPosition ?? 
                    Offset(
                      MediaQuery.sizeOf(context).width / 2,
                      MediaQuery.sizeOf(context).height - 50,
                    );

                return ClipPath(
                  clipper: _LiquidRevealClipper(
                    fraction: curve.value,
                    center: center,
                  ),
                  // We add a subtle scale to the new page so it "swells" into existence
                  // alongside the circular mask, enhancing the liquid feel.
                  child: Transform.scale(
                    scale: 0.95 + (0.05 * curve.value),
                    child: Opacity(
                      // Quick fade in at the very beginning to avoid harsh edges
                      opacity: curve.value < 0.05 ? curve.value / 0.05 : 1.0,
                      child: childWidget,
                    ),
                  ),
                );
              },
              child: child,
            );
          },
        );
}

class _LiquidRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;

  _LiquidRevealClipper({
    required this.fraction,
    required this.center,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    
    // Maximum distance from the tap point to the furthest corner of the screen
    final maxRadius = _calcMaxRadius(size, center);
    
    // Current radius based on animation fraction
    final radius = maxRadius * fraction;

    path.addOval(Rect.fromCircle(center: center, radius: radius));
    return path;
  }

  double _calcMaxRadius(Size size, Offset center) {
    final w = math.max(center.dx, size.width - center.dx);
    final h = math.max(center.dy, size.height - center.dy);
    return math.sqrt(w * w + h * h);
  }

  @override
  bool shouldReclip(_LiquidRevealClipper oldClipper) {
    return oldClipper.fraction != fraction || oldClipper.center != center;
  }
}

/// A cinematic content-slide transition for the Watch Screen.
///
/// The outgoing page's content slides to the left and fades out,
/// while the incoming page's content slides in from the right and fades in.
/// Both pages share the same dark background and backdrop image,
/// creating the illusion of persistent scenery with only the overlaid
/// UI elements moving.
class CinematicSlideRoute extends PageRouteBuilder {
  final Widget page;

  CinematicSlideRoute({
    required this.page,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 600),
          reverseTransitionDuration: const Duration(milliseconds: 500),
          opaque: true,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Incoming page: slide from right + fade in
            final inCurve = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.25, 0.1, 0.25, 1.0),
              reverseCurve: Curves.easeInCubic,
            );

            final slideIn = Tween<Offset>(
              begin: const Offset(0.15, 0),
              end: Offset.zero,
            ).animate(inCurve);

            final fadeIn = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            ));

            return SlideTransition(
              position: slideIn,
              child: FadeTransition(
                opacity: fadeIn,
                child: child,
              ),
            );
          },
        );
}
