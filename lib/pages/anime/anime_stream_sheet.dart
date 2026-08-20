import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/anime/anime_media.dart';
import '../../models/stream/stream_model.dart';
import '../../services/anime/anime_scraper_service.dart';
import '../../services/anime/anime_stream_service.dart';
import '../player/player_screen.dart';

class AnimeStreamSheet extends StatefulWidget {
  final AnimeMedia anime;
  final int episodeNumber;
  final bool autoPlay;
  final bool isDub;

  const AnimeStreamSheet({
    super.key,
    required this.anime,
    required this.episodeNumber,
    this.autoPlay = false,
    this.isDub = false,
  });

  @override
  State<AnimeStreamSheet> createState() => _AnimeStreamSheetState();
}

class _AnimeStreamSheetState extends State<AnimeStreamSheet> {
  final AnimeScraperService _scraper = AnimeScraperService.instance;

  final List<StreamSource> _sources = [];
  bool _isScraping = true;
  String? _error;
  StreamSubscription<StreamSource>? _streamSub;

  List<StreamSource> get _filteredSources {
    final isDub = widget.isDub;
    return _sources
        .where((s) => ((s.description?.contains('Dub') ?? false) == isDub))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _startScraping();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  void _startScraping() {
    setState(() {
      _sources.clear();
      _isScraping = true;
      _error = null;
    });

    _streamSub = _scraper
        .scrapeStreamsStream(
      anime: widget.anime,
      episodeNumber: widget.episodeNumber,
    )
        .listen(
      (source) {
        if (mounted) {
          setState(() {
            _sources.add(source);
          });

          if (widget.autoPlay &&
              _filteredSources.length == 1 &&
              identical(_filteredSources.first, source)) {
            _playSource(source);
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isScraping = false;
            _error = e.toString();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isScraping = false;
            if (_filteredSources.isEmpty) {
              _error = widget.isDub
                  ? 'No dub streams found for Episode ${widget.episodeNumber}.'
                  : 'No sub streams found for Episode ${widget.episodeNumber}.';
            }
          });
        }
      },
    );
  }

  Future<void> _playSource(StreamSource source) async {
    final detail = AnimeScraperService.toMovieDetail(widget.anime);
    final video = AnimeScraperService.toVideo(widget.anime, widget.episodeNumber);

    // Enrich playback with the stream resolver: provider headers (Referer/
    // Origin), subtitle tracks, and AniSkip intro/outro times when available.
    final resolved = await AnimeStreamService.instance.getEpisodeStream(
      anime: widget.anime,
      episodeNumber: widget.episodeNumber,
      isDub: widget.isDub,
    );

    final enriched = StreamSource(
      name: source.name,
      title: source.title,
      url: source.url,
      description: source.description,
      addonName: source.addonName,
      headers: {
        ...?source.headers,
        ...?resolved?.headers,
      },
      behaviorHints: {
        ...?source.behaviorHints,
        if (resolved != null) 'animeStream': {
          if (resolved.introStart != null) 'introStart': resolved.introStart,
          if (resolved.introEnd != null) 'introEnd': resolved.introEnd,
          if (resolved.outroStart != null) 'outroStart': resolved.outroStart,
          if (resolved.outroEnd != null) 'outroEnd': resolved.outroEnd,
          'subtitles': resolved.subtitles
              .map((s) => {'url': s.url, 'lang': s.lang, 'label': s.label})
              .toList(),
        },
      },
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: enriched,
          title: '${widget.anime.displayTitle} - Episode ${widget.episodeNumber}',
          backdropUrl: widget.anime.backdropUrl,
          detail: detail,
          episode: video,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F121C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.anime.displayTitle} • Ep ${widget.episodeNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (_isScraping) ...[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF7C5CFF),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Scraping stream sources...',
                              style: TextStyle(
                                color: Color(0xFF7C5CFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else
                            Text(
                              '${_filteredSources.length} ${widget.isDub ? 'dub' : 'sub'} sources found',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          // Stream list
          Flexible(
            child: _filteredSources.isEmpty && _isScraping
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                        SizedBox(height: 14),
                        Text(
                          'Fetching Miruro, Gogoanime & HiAnime streams...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _filteredSources.isEmpty && _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.redAccent,
                              size: 40,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C5CFF),
                              ),
                              onPressed: _startScraping,
                              child: const Text('Retry Scraping'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredSources.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final s = _filteredSources[index];
                          final isDub =
                              s.description?.contains('Dub') ?? false;

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _playSource(s),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF191C28),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C5CFF)
                                            .withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: Color(0xFF7C5CFF),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.name ?? 'Stream Source',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            s.description ?? s.addonName,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDub
                                            ? Colors.orange.withValues(alpha: 0.2)
                                            : Colors.blue.withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isDub ? 'DUB' : 'SUB',
                                        style: TextStyle(
                                          color: isDub
                                              ? Colors.orangeAccent
                                              : Colors.lightBlueAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
