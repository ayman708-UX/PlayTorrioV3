// Port of `ChannelText.kt` + `TeamNameKeys.kt` from `features/sports`.
//
// Pure Dart accent folding (no external deps) so it works on all targets.

class ChannelText {
  static final Map<int, String> _deburrMap = _buildDeburr();

  static Map<int, String> _buildDeburr() {
    final map = <int, String>{};
    void add(String chars, String plain) {
      for (final c in chars.split('')) {
        map[c.codeUnitAt(0)] = plain;
      }
    }

    add('àáâãäåāăąằắặẳ', 'a');
    add('çćĉċč', 'c');
    add('ďđ', 'd');
    add('èéêëēĕėęě', 'e');
    add('ĝğġģ', 'g');
    add('ĥħ', 'h');
    add('ìíîïĩīĭįı', 'i');
    add('ĵ', 'j');
    add('ķĸ', 'k');
    add('ĺļľł', 'l');
    add('ñńņňŉ', 'n');
    add('òóôõöøōŏő', 'o');
    add('ŕŗř', 'r');
    add('śŝşš', 's');
    add('ťŧ', 't');
    add('ùúûüũūŭůűų', 'u');
    add('ŵ', 'w');
    add('ýÿŷ', 'y');
    add('źżž', 'z');
    return map;
  }

  static String deburr(String text) {
    if (text.isEmpty) return text;
    final sb = StringBuffer();
    for (final rune in text.runes) {
      final lower = String.fromCharCode(rune).toLowerCase();
      if (lower.isNotEmpty && _deburrMap.containsKey(lower.codeUnitAt(0))) {
        sb.write(_deburrMap[lower.codeUnitAt(0)]);
      } else {
        sb.write(lower);
      }
    }
    return sb.toString();
  }

  /// Lowercase + accent-fold + collapse whitespace + trim.
  static String normalize(String text) {
    return deburr(text)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static final RegExp _qualityTag = RegExp(
    r'(?:[\s\-_/]*[\(\[]?(?:sd|hd|fhd|uhd|qhd|hq|4k|8k|hevc|h265|50fps|60fps)[\)\]]?\s*)+$',
    caseSensitive: false,
  );

  static String stripQualitySuffix(String name) {
    return name.replaceAll(_qualityTag, '').trim();
  }

  /// Combined: deburr + lowercase + strip quality + collapse whitespace.
  static String channelNameKey(String name) {
    return normalize(stripQualitySuffix(name));
  }
}

class TeamNameKeys {
  static final RegExp _trailingClub = RegExp(
    r'\s+(?:fc|ac|cf|sc|afc|sfc|united|city)$',
    caseSensitive: false,
  );
  static final RegExp _leadingClub = RegExp(
    r'^(?:fc|sc|ac|as|afc|vfl|vfb|ssc|ss|us|rc|rcd|cd|ca|sv|ogc|sport[\-\s]?club)\s+',
    caseSensitive: false,
  );

  static const Map<String, List<String>> _manualAliases = {
    'manchester united': ['man utd', 'manchester utd'],
    'manchester city': ['man city'],
    'wolverhampton': ['wolves', 'wolverhampton wanderers'],
    'tottenham': ['spurs', 'tottenham hotspur'],
    'chelsea': ['chelsea fc'],
    'newcastle united': ['newcastle'],
    'west ham united': ['west ham'],
    'barcelona': ['fc barcelona'],
    'real madrid': ['real madrid cf'],
    'inter milan': ['inter'],
    'ac milan': ['ac milan'],
    'juventus': ['juventus fc'],
    'bayern munich': ['bayern'],
    'borussia dortmund': ['dortmund'],
    'psg': ['paris saint-germain'],
    'new york yankees': ['yankees'],
    'boston red sox': ['red sox'],
    'los angeles lakers': ['lakers'],
    'golden state warriors': ['warriors'],
    'dallas cowboys': ['cowboys'],
  };

  static const Set<String> _ambiguousFirstWord = {
    'real', 'city', 'sport', 'sports', 'live', 'team', 'club', 'next',
    'united', 'inter', 'first', 'last', 'home', 'away', 'sky', 'star',
    'super', 'best', 'news', 'football', 'soccer', 'channel',
    'fc', 'ac', 'sc', 'la', 'el', 'red', 'blue', 'white', 'black',
    'north', 'south', 'east', 'west', 'new', 'st', 'san', 'los', 'de',
  };

  static const Set<String> _usLeagues = {'mlb', 'nba', 'nfl', 'nhl', 'wnba', 'mls'};

  static bool isAmbiguousFirstWord(String word) =>
      _ambiguousFirstWord.contains(word);

  static List<String> expand(String name, [String league = '']) {
    final normalized = ChannelText.channelNameKey(name);
    if (normalized.isEmpty) return const [];
    final keys = <String>{normalized};

    final noTrailing = normalized.replaceAll(_trailingClub, '').trim();
    if (noTrailing != normalized && noTrailing.isNotEmpty) keys.add(noTrailing);

    final noLeading = noTrailing.replaceAll(_leadingClub, '').trim();
    if (noLeading.isNotEmpty && noLeading != noTrailing) keys.add(noLeading);

    final firstWord = noTrailing.split(' ').firstOrNull;
    if (firstWord != null &&
        firstWord.length >= 4 &&
        !isAmbiguousFirstWord(firstWord)) {
      keys.add(firstWord);
    }

    if (_usLeagues.contains(league.toLowerCase())) {
      final tokens = noTrailing.split(' ');
      final last = tokens.lastOrNull;
      if (last != null && last.length >= 4 && last != firstWord) {
        keys.add(last);
      }
    }

    _manualAliases[normalized]?.forEach(keys.add);
    return keys.toList();
  }
}
