import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/playback_coordinator.dart';

/// A universal bottom play bar shown across all hubs (Media, Books, Music).
///
/// It reflects whatever is currently playing (music, video, or audiobook) via
/// the global [PlaybackCoordinator], with a play/pause toggle and a stop
/// button. It sits above the AppDock so it never overlaps the hub switcher.
class UniversalPlayBar extends StatelessWidget {
  const UniversalPlayBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: PlaybackCoordinator.revision,
      builder: (context, _, __) {
        if (!PlaybackCoordinator.hasActive) return const SizedBox.shrink();

        final title = PlaybackCoordinator.title ?? 'Now Playing';
        final subtitle = PlaybackCoordinator.subtitle ?? '';
        final coverUrl = PlaybackCoordinator.coverUrl;
        final isPlaying = PlaybackCoordinator.isPlaying;
        final kind = PlaybackCoordinator.activeKind;

        final isMobile = MediaQuery.sizeOf(context).width < 600;

        final durMs = PlaybackCoordinator.duration.inMilliseconds;
        final posMs = PlaybackCoordinator.position.inMilliseconds;
        final progress =
            durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0).toDouble() : 0.0;

        return GestureDetector(
          onTap: PlaybackCoordinator.expand,
          child: Container(
            height: 60,
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF131522).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF7C5CFF).withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Row(
                  children: [
              // Cover / icon
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _kindIcon(kind),
                      )
                    : _kindIcon(kind),
              ),
              const SizedBox(width: 12),
              // Title / artist — independently tappable.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Song / media title → open the full player.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: PlaybackCoordinator.expand,
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      // Artist / subtitle → open the artist (music) when possible.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: PlaybackCoordinator.openArtist,
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                Text(
                  _kindLabel(kind),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Play / Pause
              IconButton(
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  color: const Color(0xFF7C5CFF),
                  size: 34,
                ),
                onPressed: PlaybackCoordinator.togglePlayPause,
              ),
              // Stop
              IconButton(
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.white60,
                  size: 26,
                ),
                onPressed: PlaybackCoordinator.stopActive,
              ),
              // Close (dismiss the bar)
              IconButton(
                tooltip: 'Close',
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
                onPressed: PlaybackCoordinator.dismiss,
              ),
            ],
                ),
                // Thin progress bar along the bottom edge.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: durMs > 0 ? progress : null,
                    minHeight: 3,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFF7C5CFF),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kindIcon(String? kind) {
    final icon = switch (kind) {
      'music' => Icons.music_note_rounded,
      'video' => Icons.movie_rounded,
      'audiobook' => Icons.headphones_rounded,
      _ => Icons.play_arrow_rounded,
    };
    return Container(
      width: 40,
      height: 40,
      color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
      child: Icon(icon, color: const Color(0xFF7C5CFF), size: 22),
    );
  }

  String _kindLabel(String? kind) {
    return switch (kind) {
      'music' => 'MUSIC',
      'video' => 'VIDEO',
      'audiobook' => 'AUDIOBOOK',
      _ => 'PLAYING',
    };
  }
}
