// Port of `MultiWindowPlayerEngine.kt` + its Android actual.
//
// In the Kotlin app each cell owns an ExoPlayer. In Flutter we get the same
// media3 backend through `video_player` (with `fvp` registered in main.dart as
// the platform implementation), so each cell owns a `VideoPlayerController`.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'multi_window_store.dart';

/// Bounded manager that owns up to [maxPlayers] concurrent `VideoPlayerController`s
/// keyed by multi-window stream id (mirrors `MultiWindowPlayerManager`).
class MultiWindowPlayerManager {
  MultiWindowPlayerManager._();

  static final MultiWindowPlayerManager instance =
      MultiWindowPlayerManager._();

  static const int maxPlayers = 9;

  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, double> _savedVolumes = {};

  /// Creates + initializes a player for [streamId]. Returns once the controller
  /// is ready, or null when the URL fails to initialize.
  Future<VideoPlayerController?> createPlayer(
    String streamId,
    String sourceUrl, {
    Map<String, String> headers = const {},
    VoidCallback? onCompletion,
  }) async {
    // Respect the player cap: release the oldest stream when full.
    if (_controllers.length >= maxPlayers) {
      final oldest = _controllers.keys.first;
      await releasePlayer(oldest);
    }

    final existing = _controllers[streamId];
    if (existing != null) return existing;

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(sourceUrl),
      httpHeaders: headers,
    );
    try {
      await controller.initialize();
    } catch (_) {
      controller.dispose();
      return null;
    }
    controller.setLooping(false);
    if (onCompletion != null) {
      controller.addListener(() {
        if (controller.value.position >= controller.value.duration &&
            controller.value.isPlaying == false &&
            controller.value.isInitialized &&
            controller.value.hasError == false) {
          onCompletion();
        }
      });
    }
    _controllers[streamId] = controller;
    return controller;
  }

  VideoPlayerController? controllerFor(String streamId) =>
      _controllers[streamId];

  void setVolume(String streamId, double volume) {
    _controllers[streamId]?.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Mutes every other player and restores this one to its saved volume.
  void setAudioFocus(String streamId) {
    for (final entry in _controllers.entries) {
      final controller = entry.value;
      if (entry.key == streamId) {
        controller.setVolume(_savedVolumes.remove(streamId) ?? 1.0);
      } else {
        _savedVolumes.putIfAbsent(entry.key, () => controller.value.volume);
        controller.setVolume(0.0);
      }
    }
  }

  void pausePlayer(String streamId) =>
      _controllers[streamId]?.pause();

  void resumePlayer(String streamId) =>
      _controllers[streamId]?.play();

  Future<void> releasePlayer(String streamId) async {
    final controller = _controllers.remove(streamId);
    _savedVolumes.remove(streamId);
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> releaseAll() async {
    for (final id in List.of(_controllers.keys)) {
      await releasePlayer(id);
    }
    _savedVolumes.clear();
  }
}

/// Renders a multi-window cell's video surface. Mirrors `MultiWindowVideoSurface`.
class MultiWindowVideoSurface extends StatelessWidget {
  const MultiWindowVideoSurface({
    super.key,
    required this.controller,
    this.resizeMode = resizeFill,
  });

  final VideoPlayerController? controller;
  final int resizeMode;

  static BoxFit _fitFor(int mode) {
    switch (mode) {
      case resizeFit:
        return BoxFit.contain;
      case resizeFixedWidth:
        return BoxFit.fitWidth;
      case resizeFixedHeight:
        return BoxFit.fitHeight;
      case resizeZoom:
        return BoxFit.cover;
      case resizeFill:
      default:
        return BoxFit.fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }
    final fit = _fitFor(resizeMode);
    return SizedBox.expand(
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: VideoPlayer(controller),
      ),
    );
  }
}