import 'package:flutter/material.dart';

import '../../main.dart';

/// Pushes a route onto the **root** navigator so it renders fullscreen,
/// escaping the hub's nested navigator. Use this for fullscreen playback
/// (video player, audiobook player, manga reader, etc.).
Future<T?> pushFullscreen<T>(Route<T> route) {
  return navigatorKey.currentState!.push<T>(route);
}

/// Replaces the current route on the **root** navigator (fullscreen).
Future<T?> pushFullscreenReplacement<T>(Route<T> route) {
  return navigatorKey.currentState!.pushReplacement<T, dynamic>(route);
}
