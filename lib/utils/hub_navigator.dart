import 'package:flutter/foundation.dart';

/// Allows child hub pages (hosted inside [HubPage]'s IndexedStack) to request
/// navigation back to the primary "Movies & Series" hub without popping the
/// app root (which would leave a black screen).
///
/// [HubPage] registers a callback in `initState`; hub pages with a back button
/// call [goHome] instead of `Navigator.pop`.
abstract final class HubNavigator {
  static VoidCallback? _onGoHome;

  /// Registers the callback that switches the active hub to "Movies & Series".
  static void registerGoHome(VoidCallback callback) {
    _onGoHome = callback;
  }

  /// Switches back to the primary media hub. Safe to call even if no callback
  /// is registered (no-op).
  static void goHome() {
    _onGoHome?.call();
  }
}