import '../subtitle/subtitle_model.dart';

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
  final String? providerId;
  final String? providerName;
  final List<SubtitleVariant>? subtitles;

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
    this.providerId,
    this.providerName,
    this.subtitles,
  });

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
    String? providerId,
    String? providerName,
    List<SubtitleVariant>? subtitles,
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
      providerId: providerId ?? this.providerId,
      providerName: providerName ?? this.providerName,
      subtitles: subtitles ?? this.subtitles,
    );
  }

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

    Map<String, String>? headersMap;
    if (json['headers'] is Map) {
      headersMap = (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } else if (hints != null) {
      if (hints['proxyHeaders'] is Map && (hints['proxyHeaders'] as Map)['request'] is Map) {
        headersMap = ((hints['proxyHeaders'] as Map)['request'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      } else if (hints['requestHeaders'] is Map) {
        headersMap = (hints['requestHeaders'] as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    }

    List<SubtitleVariant>? subs;
    final rawSubs = json['subtitles'] ?? hints?['subtitles'];
    if (rawSubs is List) {
      subs = [];
      for (final s in rawSubs) {
        if (s is Map) {
          final file = s['url']?.toString() ?? s['file']?.toString();
          if (file != null && file.isNotEmpty) {
            final lang = s['lang']?.toString() ?? s['language']?.toString() ?? s['label']?.toString() ?? 'English';
            subs.add(SubtitleVariant(
              providerName: addonName,
              language: lang,
              title: s['title']?.toString() ?? '$lang ($addonName)',
              downloadUrl: file,
              format: (s['format']?.toString() ?? (file.contains('.vtt') ? 'vtt' : 'srt')).toLowerCase(),
              extraData: s['headers'] is Map ? {'headers': Map<String, String>.from(s['headers'] as Map)} : const {},
            ));
          }
        }
      }
      if (subs.isEmpty) subs = null;
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
      headers: headersMap,
      providerId: json['providerId']?.toString(),
      providerName: json['providerName']?.toString(),
      subtitles: subs,
    );
  }

  static final RegExp _fileSizeRegex = RegExp(
    r'(\d+(?:[\.,]\d+)?)\s*(TB|TiB|GB|GiB|MB|MiB|KB|KiB)|(TB|TiB|GB|GiB|MB|MiB|KB|KiB)\s*(\d+(?:[\.,]\d+)?)',
    caseSensitive: false,
  );

  static final List<RegExp> _seederPatterns = [
    RegExp(r'[👤👥🌱⚡]\s*(\d+)', caseSensitive: false),
    RegExp(r'(?:seeds?|seeders?|peers?|s)\s*[:=]\s*(\d+)', caseSensitive: false),
    RegExp(r'(\d+)\s*(?:seeds?|seeders?)', caseSensitive: false),
    RegExp(r'\[\s*(\d+)\s*(?:s|seeds?)', caseSensitive: false),
    RegExp(r'/\s*(\d+)\s*peers?', caseSensitive: false),
    RegExp(r'(\d+)\s*/\s*\d+\s*(?:peers?|seeds?)?', caseSensitive: false),
  ];

  String? _cachedQuality;
  bool _qualityComputed = false;
  /// Extract resolution badge from title/name text.
  String? get quality {
    if (_qualityComputed) return _cachedQuality;
    _qualityComputed = true;
    final text = '${title ?? ''} ${name ?? ''}'.toLowerCase();
    if (text.contains('2160') || text.contains('4k') || text.contains('uhd')) return _cachedQuality = '4K';
    if (text.contains('1080')) return _cachedQuality = '1080p';
    if (text.contains('720')) return _cachedQuality = '720p';
    if (text.contains('480')) return _cachedQuality = '480p';
    return _cachedQuality = null;
  }

  static final RegExp _multiAudioRegex = RegExp(
    r'(?:'
    r'\|\s*MULTI\b|'
    r'\bmulti[- ]?audio\b|'
    r'\bdual[- ]?audio\b|'
    r'\bdual\b(?=[\s.·|\[\]\(\)-]|$)|'
    r'\bmulti\b(?=[\s.·|\[\]\(\)-]|$)(?!-?cdn|-?server|-?embed|-?vid|-?sub)'
    r')',
    caseSensitive: false,
  );

  static final RegExp _hindiIndianRegex = RegExp(
    r'\b(hindi|hindiv3|hindicast|tamil|telugu|malayalam|kannada|punjabi|marathi|bengali|bollywood)\b(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  static final RegExp _germanRegex = RegExp(
    r'\b(german|deutsch|munich|berlin|ger)\b(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  static final RegExp _frenchRegex = RegExp(
    r'\b(french|francais|français|paris|truefrench|vff|vfi|fre)\b(?![- ]?(?:sub|subbed|subs|subtitles))|\bvf\b',
    caseSensitive: false,
  );

  static final RegExp _castilianRegex = RegExp(
    r'\b(castellano|castellana|castilian|es[-_]es|spa[- ]?castellano|esp[- ]?castellano|audio[- ]?castellano|spanish\s*\(\s*spain\s*\)|español\s*de\s*españa|espanol\s*de\s*espana)\b(?![- ]?(?:sub|subbed|subs|subtitles))|\[cast\]|\(cast\)',
    caseSensitive: false,
  );

  static final RegExp _latinoRegex = RegExp(
    r'\b(latino|latina|latam|latin[- ]?audio|audio[- ]?latino|es[-_](?:la|419|mx|ar|co|cl)|spanish\s*\(\s*latin(?:\s*america)?\s*\)|español\s*latino|espanol\s*latino)\b(?![- ]?(?:sub|subbed|subs|subtitles))|(?<=[^a-z0-9]|^)lat(?=[^a-z0-9]|$)(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  static final RegExp _spanishRegex = RegExp(
    r'\b(spanish|espanol|español|cancun|latino|latina|latam|castellano|castellana|castilian|spa|esp|es[-_](?:es|la|419|mx|ar|co|cl))\b(?![- ]?(?:sub|subbed|subs|subtitles))|(?<=[^a-z0-9]|^)lat(?=[^a-z0-9]|$)(?![- ]?(?:sub|subbed|subs|subtitles))|\[cast\]|\(cast\)',
    caseSensitive: false,
  );

  static final RegExp _russianRegex = RegExp(
    r'\b(russian|rus|ukr|ukrainian)\b(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  static final RegExp _japaneseRegex = RegExp(
    r'\b(japanese|jpn)\b(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  static final RegExp _italianRegex = RegExp(
    r'\b(italian|ita)\b(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  static final RegExp _englishRegex = RegExp(
    r'\b(eng|english|original audio|miami|seattle|denver|chicago|dallas|atlanta|houston|boston)\b(?![- ]?(?:sub|subbed|subs|subtitles))',
    caseSensitive: false,
  );

  /// Returns detected audio languages for this stream.
  /// Standard keys: 'multi', 'english', 'hindi', 'german', 'french', 'spanish', 'spanish_castilian', 'spanish_latino', 'russian', 'japanese', 'italian'.
  Set<String> getAudioLanguages({String? mediaTitle}) {
    final tags = <String>{};
    var fullText = '${title ?? ''} ${name ?? ''} ${description ?? ''}';

    if (mediaTitle != null && mediaTitle.trim().isNotEmpty) {
      final sanitized = RegExp.escape(mediaTitle.trim());
      fullText = fullText.replaceAll(RegExp(sanitized, caseSensitive: false), ' ');
    }

    // Strip explicit subtitle listings so they don't trigger audio tags
    fullText = fullText.replaceAll(
      RegExp(r'\b(?:subs?|subtitles?)\s*[:=]\s*.*$', multiLine: true, caseSensitive: false),
      ' ',
    );

    if (_multiAudioRegex.hasMatch(fullText)) tags.add('multi');
    if (_hindiIndianRegex.hasMatch(fullText)) tags.add('hindi');
    if (_germanRegex.hasMatch(fullText)) tags.add('german');
    if (_frenchRegex.hasMatch(fullText)) tags.add('french');

    final isCastilian = _castilianRegex.hasMatch(fullText);
    final isLatino = _latinoRegex.hasMatch(fullText);
    final isSpanish = isCastilian || isLatino || _spanishRegex.hasMatch(fullText);

    if (isCastilian) tags.add('spanish_castilian');
    if (isLatino) tags.add('spanish_latino');
    if (isSpanish) tags.add('spanish');

    if (_russianRegex.hasMatch(fullText)) tags.add('russian');
    if (_japaneseRegex.hasMatch(fullText)) tags.add('japanese');
    if (_italianRegex.hasMatch(fullText)) tags.add('italian');

    final hasRegional = tags.any((t) => t != 'multi');
    if (_englishRegex.hasMatch(fullText) || !hasRegional) {
      tags.add('english');
    }

    return tags;
  }

  /// Whether this stream source matches the selected audio filter key.
  bool hasAudioLanguage(String filterKey, {String? mediaTitle}) {
    if (filterKey == 'all') return true;
    final langs = getAudioLanguages(mediaTitle: mediaTitle);
    return langs.contains(filterKey);
  }

  /// Returns a clean UI badge label if a special or regional dub is detected.
  String? getAudioBadge({String? mediaTitle}) {
    final langs = getAudioLanguages(mediaTitle: mediaTitle);

    // If both Spanish dubs are present
    if (langs.contains('spanish_castilian') && langs.contains('spanish_latino')) {
      return '🇪🇸 CAST / 🇲🇽 LAT';
    }

    // If multiple distinct regional language families are present with multi, badge as MULTI
    final nonSpanishRegional = langs.where((l) =>
        l != 'multi' &&
        l != 'english' &&
        l != 'spanish' &&
        l != 'spanish_castilian' &&
        l != 'spanish_latino').length;
    final hasSpanish = langs.contains('spanish');
    final distinctRegionalCount = nonSpanishRegional + (hasSpanish ? 1 : 0);

    if (distinctRegionalCount > 1 && langs.contains('multi')) {
      return '🌐 MULTI';
    }

    if (langs.contains('spanish_castilian')) return '🇪🇸 CAST';
    if (langs.contains('spanish_latino')) return '🇲🇽 LAT';
    if (langs.contains('spanish')) return '🇪🇸 SPA';

    if (langs.contains('hindi')) {
      final text = '${title ?? ''} ${name ?? ''} ${description ?? ''}'.toLowerCase();
      if (text.contains('telugu')) return '🇮🇳 TELUGU';
      if (text.contains('tamil')) return '🇮🇳 TAMIL';
      if (text.contains('malayalam')) return '🇮🇳 MALAYALAM';
      if (text.contains('kannada')) return '🇮🇳 KANNADA';
      if (text.contains('punjabi')) return '🇮🇳 PUNJABI';
      return '🇮🇳 HINDI';
    }
    if (langs.contains('german')) return '🇩🇪 GER';
    if (langs.contains('french')) return '🇫🇷 FRE';
    if (langs.contains('russian')) return '🇷🇺 RUS';
    if (langs.contains('japanese')) return '🇯🇵 JPN';
    if (langs.contains('italian')) return '🇮🇹 ITA';
    if (langs.contains('multi')) return '🌐 MULTI';

    final text = '${title ?? ''} ${name ?? ''} ${description ?? ''}';
    if (RegExp(r'\b(eng|english)\b', caseSensitive: false).hasMatch(text)) {
      return '🇺🇸 ENG';
    }
    return null;
  }

  bool? _cachedHDR;
  /// Extract HDR badge.
  bool get isHDR {
    if (_cachedHDR != null) return _cachedHDR!;
    final text = '${title ?? ''} ${name ?? ''}'.toLowerCase();
    return _cachedHDR = (text.contains('hdr') ||
        text.contains('dolby vision') ||
        text.contains('dv'));
  }

  String? _cachedCodec;
  bool _codecComputed = false;
  /// Extract codec info.
  String? get codec {
    if (_codecComputed) return _cachedCodec;
    _codecComputed = true;
    final text = '${title ?? ''} ${name ?? ''}'.toLowerCase();
    if (text.contains('hevc') || text.contains('x265') || text.contains('h.265') || text.contains('h265')) return _cachedCodec = 'HEVC';
    if (text.contains('x264') || text.contains('h.264') || text.contains('h264') || text.contains('avc')) return _cachedCodec = 'H.264';
    if (text.contains('av1')) return _cachedCodec = 'AV1';
    return _cachedCodec = null;
  }

  String? _cachedFileSize;
  bool _fileSizeComputed = false;
  /// Extract file size string if mentioned in title, name, or description.
  String? get fileSize {
    if (_fileSizeComputed) return _cachedFileSize;
    _fileSizeComputed = true;
    final text = '${title ?? ''} ${name ?? ''} ${description ?? ''}';
    final match = _fileSizeRegex.firstMatch(text);
    if (match != null) {
      final numStr = match.group(1) ?? match.group(4);
      final unit = (match.group(2) ?? match.group(3))?.toUpperCase();
      if (numStr != null && unit != null) {
        return _cachedFileSize = '$numStr $unit';
      }
    }
    return _cachedFileSize = null;
  }

  double? _cachedSizeBytes;
  bool _sizeBytesComputed = false;
  /// Extracted size in bytes for filtering and sorting.
  double? get sizeBytes {
    if (_sizeBytesComputed) return _cachedSizeBytes;
    _sizeBytesComputed = true;
    final text = '${title ?? ''} ${name ?? ''} ${description ?? ''}';
    final match = _fileSizeRegex.firstMatch(text);
    if (match != null) {
      final numStr = match.group(1) ?? match.group(4);
      final unit = (match.group(2) ?? match.group(3))?.toUpperCase();
      if (numStr != null && unit != null) {
        final val = double.tryParse(numStr.replaceAll(',', '.'));
        if (val != null) {
          if (unit.startsWith('T')) return _cachedSizeBytes = val * 1024 * 1024 * 1024 * 1024;
          if (unit.startsWith('G')) return _cachedSizeBytes = val * 1024 * 1024 * 1024;
          if (unit.startsWith('M')) return _cachedSizeBytes = val * 1024 * 1024;
          if (unit.startsWith('K')) return _cachedSizeBytes = val * 1024;
        }
      }
    }
    return _cachedSizeBytes = null;
  }

  static final RegExp _bitrateRegex = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(mbps|mb/s|mbit/s|kbps|kb/s|kbit/s)',
    caseSensitive: false,
  );

  int? _cachedBitrateKbps;
  bool _bitrateComputed = false;
  /// Extract video bitrate in kbps if mentioned in title, name, or description.
  /// Audio-only rates (e.g. "AAC 128kbps") are ignored via the 500kbps floor.
  int? get bitrateKbps {
    if (_bitrateComputed) return _cachedBitrateKbps;
    _bitrateComputed = true;
    final text = '${title ?? ''} ${name ?? ''} ${description ?? ''}';
    final match = _bitrateRegex.firstMatch(text);
    if (match != null) {
      final val = double.tryParse((match.group(1) ?? '').replaceAll(',', '.'));
      final unit = (match.group(2) ?? '').toLowerCase();
      if (val != null) {
        final kbps = unit.startsWith('m') ? val * 1000 : val;
        if (unit.startsWith('m') ? kbps >= 200 : kbps >= 500) {
          return _cachedBitrateKbps = kbps.round();
        }
      }
    }
    return _cachedBitrateKbps = null;
  }

  /// Rough bitrate derived from file size and runtime in minutes.
  /// Used for torrent/debrid sources that don't state a bitrate anywhere.
  int? estimatedBitrateKbps(int? runtimeMinutes) {
    final known = bitrateKbps;
    if (known != null) return known;
    final sz = sizeBytes;
    if (sz == null || runtimeMinutes == null || runtimeMinutes <= 0) return null;
    return (sz * 8 / (runtimeMinutes * 60) / 1000).round();
  }

  /// Formatted bitrate label, e.g. '12.4 Mb/s' or '850 kb/s'.
  String? get bitrateLabel {
    final kbps = bitrateKbps;
    if (kbps == null) return null;
    return formatBitrate(kbps);
  }

  static String formatBitrate(int kbps) {
    if (kbps >= 1000) {
      return '${(kbps / 1000).toStringAsFixed(1)} Mb/s';
    }
    return '$kbps kb/s';
  }

  int? _cachedSeeders;
  bool _seedersComputed = false;
  /// Extracted seeders count from title, name, or description.
  int? get seeders {
    if (_seedersComputed) return _cachedSeeders;
    _seedersComputed = true;
    final text = '${title ?? ''} ${name ?? ''} ${description ?? ''}';
    for (final pattern in _seederPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final val = int.tryParse(match.group(1) ?? '');
        if (val != null) return _cachedSeeders = val;
      }
    }
    return _cachedSeeders = null;
  }

  int? _cachedQualityRank;
  /// Numeric quality rank for sorting (higher is better).
  int get qualityRank {
    if (_cachedQualityRank != null) return _cachedQualityRank!;
    switch (quality) {
      case '4K': return _cachedQualityRank = 4;
      case '1080p': return _cachedQualityRank = 3;
      case '720p': return _cachedQualityRank = 2;
      case '480p': return _cachedQualityRank = 1;
      default: return _cachedQualityRank = 0;
    }
  }

  /// Human-readable display title.
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    if (name != null && name!.isNotEmpty) return name!;
    return 'Unknown source';
  }

  /// Whether this source is a magnet link or torrent stream.
  bool get isMagnet =>
      (infoHash != null && infoHash!.isNotEmpty) ||
      (url != null && url!.startsWith('magnet:'));

  /// Whether this source is delivered via a Debrid cache service.
  bool get isDebrid {
    final n = (name ?? '').toLowerCase();
    final t = (title ?? '').toLowerCase();
    final u = (url ?? '').toLowerCase();
    return n.contains('[rd') || n.contains('[tb') || n.contains('[ad') || n.contains('[pm') ||
           n.contains('debrid') || t.contains('debrid') || u.contains('real-debrid') ||
           u.contains('torbox') || u.contains('alldebrid') || u.contains('premiumize');
  }

  /// Whether this source is a P2P / Torrent stream.
  bool get isTorrent => isMagnet && !isDebrid;

  /// Whether this source is a direct HTTP/HTTPS web stream.
  bool get isHttpDirect => (url != null && url!.isNotEmpty) && !isMagnet && !isDebrid;

  /// Formatted magnet link with tracker and display name parameters if available.
  String? get magnetUrl {
    if (url != null && url!.startsWith('magnet:')) {
      return url;
    }
    if (infoHash != null && infoHash!.isNotEmpty) {
      var magnet = 'magnet:?xt=urn:btih:$infoHash';
      if (title != null && title!.isNotEmpty) {
        magnet += '&dn=${Uri.encodeComponent(title!)}';
      } else if (name != null && name!.isNotEmpty) {
        magnet += '&dn=${Uri.encodeComponent(name!)}';
      }
      if (sources != null) {
        for (final src in sources!) {
          if (src.startsWith('tracker:')) {
            final trackerUrl = src.replaceFirst('tracker:', '');
            magnet += '&tr=${Uri.encodeComponent(trackerUrl)}';
          }
        }
      }
      return magnet;
    }
    return null;
  }
}
