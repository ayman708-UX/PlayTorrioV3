/// Models for Stremio stream sources.

class StreamSource {
  final String? name;
  final String? title;
  final String? url;
  final String? externalUrl;
  final String? description;
  final String? infoHash;
  final int? fileIdx;
  final String addonName;
  final Map<String, dynamic>? behaviorHints;
  final List<String>? sources;
  final Map<String, String>? headers;
  final bool torboxCached;

  StreamSource({
    this.name,
    this.title,
    this.url,
    this.externalUrl,
    this.description,
    this.infoHash,
    this.fileIdx,
    required this.addonName,
    this.behaviorHints,
    this.sources,
    this.headers,
    this.torboxCached = false,
  });

  factory StreamSource.fromJson(Map<String, dynamic> json, String addonName) {
    Map<String, dynamic>? hints;
    if (json['behaviorHints'] is Map) {
      hints = Map<String, dynamic>.from(json['behaviorHints']);
    }

    List<String>? srcList;
    if (json['sources'] is List) {
      srcList = (json['sources'] as List).map((e) => e.toString()).toList();
    }

    int? fIdx;
    if (json['fileIdx'] is int) {
      fIdx = json['fileIdx'];
    } else if (json['fileIdx'] != null) {
      fIdx = int.tryParse(json['fileIdx'].toString());
    }

    return StreamSource(
      name: json['name']?.toString(),
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      url: json['url']?.toString(),
      externalUrl: json['externalUrl']?.toString(),
      infoHash: json['infoHash']?.toString(),
      fileIdx: fIdx,
      addonName: addonName,
      behaviorHints: hints,
      sources: srcList,
    );
  }

  StreamSource copyWith({
    String? name,
    String? title,
    String? url,
    String? externalUrl,
    String? description,
    String? infoHash,
    int? fileIdx,
    String? addonName,
    Map<String, dynamic>? behaviorHints,
    List<String>? sources,
    Map<String, String>? headers,
    bool? torboxCached,
  }) {
    return StreamSource(
      name: name ?? this.name,
      title: title ?? this.title,
      url: url ?? this.url,
      externalUrl: externalUrl ?? this.externalUrl,
      description: description ?? this.description,
      infoHash: infoHash ?? this.infoHash,
      fileIdx: fileIdx ?? this.fileIdx,
      addonName: addonName ?? this.addonName,
      behaviorHints: behaviorHints ?? this.behaviorHints,
      sources: sources ?? this.sources,
      headers: headers ?? this.headers,
      torboxCached: torboxCached ?? this.torboxCached,
    );
  }

  /// Extract resolution badge from title/name text.
  String? get quality {
    final text = '${title ?? ''} ${name ?? ''}'.toLowerCase();
    if (text.contains('2160') || text.contains('4k') || text.contains('uhd')) return '4K';
    if (text.contains('1080')) return '1080p';
    if (text.contains('720')) return '720p';
    if (text.contains('480')) return '480p';
    return null;
  }

  /// Extract HDR badge.
  bool get isHDR {
    final text = '${title ?? ''} ${name ?? ''}'.toLowerCase();
    return text.contains('hdr') ||
        text.contains('dolby vision') ||
        text.contains('dv');
  }

  /// Extract codec info.
  String? get codec {
    final text = '${title ?? ''} ${name ?? ''}'.toLowerCase();
    if (text.contains('hevc') || text.contains('x265') || text.contains('h.265') || text.contains('h265')) return 'HEVC';
    if (text.contains('x264') || text.contains('h.264') || text.contains('h264') || text.contains('avc')) return 'H.264';
    if (text.contains('av1')) return 'AV1';
    return null;
  }

  /// Extract file size if mentioned in title.
  String? get fileSize {
    final text = '${title ?? ''} ${name ?? ''}';
    final regex = RegExp(r'(\d+\.?\d*)\s*(GB|MB|gb|mb|Gb|Mb)', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null) return '${match.group(1)} ${match.group(2)!.toUpperCase()}';
    return null;
  }

  /// Numeric quality rank for sorting (higher is better).
  int get qualityRank {
    switch (quality) {
      case '4K': return 4;
      case '1080p': return 3;
      case '720p': return 2;
      case '480p': return 1;
      default: return 0;
    }
  }

  /// Human-readable display title.
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    if (name != null && name!.isNotEmpty) return name!;
    return 'Unknown source';
  }
}
