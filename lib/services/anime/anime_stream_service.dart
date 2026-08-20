import '../../models/anime/anime_media.dart';
import 'miruro_stream_resolver.dart';

class AnimeStreamService {
  static final AnimeStreamService instance = AnimeStreamService._internal();
  AnimeStreamService._internal();

  final MiruroStreamResolver _resolver = MiruroStreamResolver.instance;

  List<AnimeEpisode> getEpisodes(AnimeMedia anime) {
    return _resolver.generateEpisodeList(anime);
  }

  Future<AnimeStreamResult?> getEpisodeStream({
    required AnimeMedia anime,
    required int episodeNumber,
    bool isDub = false,
  }) async {
    return await _resolver.resolveStream(
      anime: anime,
      episodeNumber: episodeNumber,
      isDub: isDub,
    );
  }
}
