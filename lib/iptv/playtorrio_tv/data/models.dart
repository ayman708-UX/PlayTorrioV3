// Models ported from PlayTorrio TV (Kotlin) IPTV system.
// Pure data classes - no Flutter dependencies.

/// Raw scraped Xtream-Codes portal credentials (unverified).
class IptvPortal {
  final String url;
  final String username;
  final String password;
  final String source;

  const IptvPortal({
    required this.url,
    required this.username,
    required this.password,
    this.source = '',
  });

  String get key => '$url|$username|$password'.toLowerCase();

  /// Identity for duplicate-portal checks: ignores URL, since the same
  /// account can be exposed on multiple host names.
  String get credKey => '$username|$password'.toLowerCase();

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'source': source,
      };

  factory IptvPortal.fromJson(Map<String, dynamic> j) => IptvPortal(
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        source: j['source'] as String? ?? '',
      );
}

/// Portal that successfully authenticated against /player_api.php.
class VerifiedPortal {
  final IptvPortal portal;
  final String name;
  final String expiry;
  final String maxConnections;
  final String activeConnections;

  const VerifiedPortal({
    required this.portal,
    required this.name,
    required this.expiry,
    required this.maxConnections,
    required this.activeConnections,
  });

  String get key => portal.key;
  String get credKey => portal.credKey;
}

class IptvCategory {
  final String id;
  final String name;
  const IptvCategory({required this.id, required this.name});
}

enum IptvSection { live, vod, series }

/// Single playable stream entry. `kind` = "live" / "vod" / "series".
class IptvStream {
  final String streamId;
  final String name;
  final String icon;
  final String categoryId;
  final String containerExt;
  final String kind;
  /// Xtream `epg_channel_id` — empty when the panel doesn't ship EPG for this
  /// channel. We don't actually need it for `get_short_epg` (that endpoint is
  /// indexed by stream_id) but it's a useful "has EPG?" hint to skip cards.
  final String epgChannelId;

  const IptvStream({
    required this.streamId,
    required this.name,
    required this.icon,
    required this.categoryId,
    required this.containerExt,
    required this.kind,
    this.epgChannelId = '',
  });
}

/// Single EPG programme entry returned by Xtream `get_short_epg`.
class EpgEntry {
  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;
  const EpgEntry({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
  });

  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(stop);
  }
}

class IptvEpisode {
  final String id;
  final String title;
  final String containerExt;
  final int season;
  final int episode;
  final String plot;
  final String image;

  const IptvEpisode({
    required this.id,
    required this.title,
    required this.containerExt,
    required this.season,
    required this.episode,
    required this.plot,
    required this.image,
  });
}

/// A single alive stream found while resolving a HardcodedChannel.
class ChannelHit {
  final VerifiedPortal portal;
  final IptvStream stream;
  final String streamUrl;

  const ChannelHit({
    required this.portal,
    required this.stream,
    required this.streamUrl,
  });
}

/// One row in the PT IPTV favorites TV guide (portal + starred live channel).
class TvGuideSlot {
  final VerifiedPortal portal;
  final IptvStream stream;

  const TvGuideSlot({
    required this.portal,
    required this.stream,
  });
}

class ScrapePage {
  final List<IptvPortal> portals;
  final String? nextAfter;
  /// If set, the Reddit catalog could not be loaded; [portals] may be empty.
  final String? catalogError;
  /// Raw M3U / playlist text captured from paste fetches (truncated in each snippet).
  final List<IptvScrapedM3uSnippet> m3uSnippets;
  const ScrapePage({
    required this.portals,
    this.nextAfter,
    this.catalogError,
    this.m3uSnippets = const [],
  });
  bool get hasMore => nextAfter != null && nextAfter!.isNotEmpty;
}

/// A chunk of text that looked like an M3U playlist from a paste/post during scrape.
class IptvScrapedM3uSnippet {
  final String source;
  final String text;
  /// Un-truncated length of the original body (if larger than [text]).
  final int originalLength;

  const IptvScrapedM3uSnippet({
    required this.source,
    required this.text,
    required this.originalLength,
  });
}
