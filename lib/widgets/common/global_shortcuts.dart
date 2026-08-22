import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/music/music_player_controller.dart';
import '../../services/playback_coordinator.dart';

/// Wraps the whole app and handles **global** keyboard shortcuts.
///
/// Music transport shortcuts (Space/K, J, L, M) work app-wide whenever music
/// is the active playback source, regardless of which hub/section is focused.
/// When a video or audiobook is the active source, those keys are left to the
/// focused widget (player screens handle their own keys).
class GlobalShortcuts extends StatefulWidget {
  final Widget child;

  const GlobalShortcuts({super.key, required this.child});

  @override
  State<GlobalShortcuts> createState() => _GlobalShortcutsState();
}

class _GlobalShortcutsState extends State<GlobalShortcuts> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'global-shortcuts');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    // Only intercept when music is the active playback source.
    if (PlaybackCoordinator.activeKind != 'music') return;

    final key = event.logicalKey;
    final player = MusicPlayerController.instance;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      player.togglePlayPause();
    } else if (key == LogicalKeyboardKey.keyJ) {
      final newPos = player.position - const Duration(seconds: 5);
      player.seekTo(newPos.inSeconds < 0 ? Duration.zero : newPos);
    } else if (key == LogicalKeyboardKey.keyL) {
      player.seekTo(player.position + const Duration(seconds: 5));
    } else if (key == LogicalKeyboardKey.keyM) {
      player.setVolume(player.volume > 0 ? 0.0 : 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
