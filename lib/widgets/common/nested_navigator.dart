import 'package:flutter/material.dart';

/// Wraps a hub's content area in its own nested [Navigator] so that detail
/// pages pushed from within the hub (movies, artists, albums, etc.) render
/// inside the content box — keeping the left sidebar and top header visible —
/// instead of taking over the full screen.
///
/// Only routes that explicitly use the root navigator (e.g. the fullscreen
/// player) escape this scope.
class NestedNavigator extends StatefulWidget {
  final Widget child;

  const NestedNavigator({super.key, required this.child});

  @override
  State<NestedNavigator> createState() => _NestedNavigatorState();
}

class _NestedNavigatorState extends State<NestedNavigator> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navigatorKey,
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return [MaterialPageRoute(builder: (_) => widget.child)];
      },
    );
  }
}
