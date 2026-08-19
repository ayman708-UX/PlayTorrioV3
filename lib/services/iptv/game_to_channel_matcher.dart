// Port of `GameToChannelMatcher.kt` from `features/sports`.
import '../../models/iptv/iptv_models.dart';

class GameToChannelMatcher {
  static const Map<String, List<String>> leagueKeywords = {
    'NFL': [
      'nfl', 'football', 'nfl network', 'nfl redzone', 'sunday night football',
      'monday night football', 'thursday night football', 'fox', 'cbs', 'nbc',
      'espn', 'sky sports nfl', 'nfl sunday', 'gridiron', 'espn2', 'espnews',
      'nfln', 'nfl network', 'paramount', 'peacock', 'prime video', 'amazon',
    ],
    'NBA': [
      'nba', 'basketball', 'nba tv', 'tnt', 'espn', 'abc', 'nba league pass',
      'sky sports nba', 'bt sport nba', 'tyson', 'nba finals', 'nbatv',
      'espn2', 'sportsnet', 'tsn',
    ],
    'MLB': [
      'mlb', 'baseball', 'mlb network', 'espn', 'fox', 'fs1', 'fs2', 'tbs',
      'mlb.tv', 'world series', 'mlbn', 'sportsnet', 'tsn',
    ],
    'NHL': [
      'nhl', 'hockey', 'nhl network', 'tnt', 'espn', 'abc', 'nhl.tv',
      'stanley cup', 'nhl center ice', 'sportsnet', 'cbc', 'tsn',
    ],
    'MLS': [
      'mls', 'soccer', 'fox soccer', 'apple tv', 'mls season pass', 'football',
      'fs1', 'fs2', 'espn', 'tsn',
    ],
    'UFC': [
      'ufc', 'mma', 'espn', 'espn+', 'espn2', 'ufc fight pass', 'tnt sports',
      'bt sport', 'dazn', 'fight night', 'ufc ppv', 'tnt sport 1',
      'tnt sport 2', 'sky sports arena',
    ],
    'BOX': [
      'boxing', 'fight', 'espn', 'dazn', 'showtime', 'sky sports boxing',
      'bt sport boxing', 'matchroom', 'top rank', 'ppv', 'title fight',
      'tnt sports', 'dazn 1', 'dazn 2',
    ],
    'PFL': ['pfl', 'mma', 'espn2', 'espn', 'espn+', 'dazn'],
    'F1': [
      'f1', 'formula 1', 'formula one', 'sky sports f1', 'espn', 'fox',
      'grand prix', 'motorsport', 'f1 tv', 'dazn',
    ],
    'MOTO': ['motogp', 'motorcycle', 'motorsport', 'dazn', 'bt sport', 'sport'],
    'TEN': [
      'tennis', 'atp', 'wta', 'grand slam', 'wimbledon', 'us open',
      'australian open', 'french open', 'sky sports tennis', 'tennis channel',
      'espn', 'espn2', 'eurosport',
    ],
    'GOLF': [
      'golf', 'pga', 'masters', 'open championship', 'sky sports golf',
      'golf channel', 'nbc', 'cbs', 'espn',
    ],
    'CFB': [
      'college football', 'ncaa football', 'cfb', 'espn', 'fox', 'abc', 'cbs',
      'ncaa', 'bowl game', 'college game day', 'espn2', 'sec network',
      'acc network', 'big ten network', 'btn', 'espnu',
    ],
    'CBB': [
      'college basketball', 'ncaa basketball', 'march madness', 'cbb', 'espn',
      'cbs', 'tbs', 'tru tv', 'ncaa tournament', 'final four', 'espn2',
      'sec network', 'big ten network', 'btn',
    ],
    'WNBA': ['wnba', 'women basketball', 'espn', 'espn2', 'nba tv', 'cbs', 'abc'],
    'AFL': ['afl', 'australian football', 'afl footy', 'fox footy', 'kayo', 'seven'],
    'NRL': ['nrl', 'rugby league', 'fox league', 'kayo', 'nine'],
    'RUGBY': [
      'rugby', 'rugby union', 'six nations', 'world rugby', 'premiership rugby',
      'united rugby', 'sky sports', 'bt sport', 'tnt sports',
    ],
    'EPL': [
      'premier league', 'epl', 'english football', 'sky sports',
      'sky sports premier league', 'sky sports main event', 'bt sport',
      'tnt sports', 'nbc sports', 'usa network', 'peacock', 'epl football',
      'sky sports football',
    ],
    'LALIGA': [
      'la liga', 'laliga', 'spanish football', 'espn', 'espn2', 'dazn',
      'sky sports', 'premium sport', 'barcelona', 'real madrid', 'la liga tv',
    ],
    'SERIEA': [
      'serie a', 'italian football', 'cbs', 'paramount', 'bt sport',
      'sky sport', 'sky sport italia', 'juventus', 'milan', 'inter',
    ],
    'BUNDES': [
      'bundesliga', 'german football', 'espn', 'fox', 'sky sport',
      'sky sport bundesliga', 'bayern', 'dortmund',
    ],
    'LIGUE1': [
      'ligue 1', 'french football', 'bein', 'bt sport', 'sky sport', 'psg',
    ],
    'UCL': [
      'champions league', 'ucl', 'uefa', 'sky sports', 'tnt sports',
      'bt sport', 'bt sport espn', 'cbs', 'paramount', 'espn', 'tnt sport',
    ],
    'UEL': ['europa league', 'uefa', 'sky sports', 'tnt sports', 'bt sport'],
    'CRIC': [
      'cricket', 'ipl', 'bbl', 'ashes', 'world cup', 'sky sports',
      'fox cricket', 'kayo', 'willow', 'espn cricket',
    ],
  };

  static const List<String> _nonSportsGroupKeywords = [
    'news', 'movie', 'movies', 'cinema', 'entertainment', 'kids', 'family',
    'music', 'comedy', 'drama', 'documentary', 'documentaries', 'radio',
    'adult', 'xx', 'xxx', 'general', 'shopping', 'reality', 'local news',
    'series', 'animation', 'lifestyle',
  ];

  static const List<String> _sportsCategoryIndicators = [
    'sport', 'sports', 'nfl', 'nba', 'mlb', 'nhl', 'ufc', 'football',
    'basketball', 'baseball', 'hockey', 'soccer', 'fight', 'racing', 'f1',
    'golf', 'tennis', 'espn', 'dazn', 'bein', 'arena', 'match', 'league',
    'ppv', 'box', 'super sport',
  ];

  static const List<String> _nonSportsChannelKeywords = [
    'fox news', 'fox business', 'abc news', 'cbs news', 'nbc news', 'sky news',
    'bbc news', 'cnn', 'msnbc', 'bloomberg', 'hbo', 'starz', 'cinemax',
    'disney', 'nickelodeon', 'cartoon network', 'mtv', 'vh1', 'discovery',
    'history channel', 'national geographic', 'tlc', 'hgtv', 'food network',
    'hallmark', 'weather channel', 'qvc', 'hsn', 'cbs drama', 'cbs reality',
    'cbs justice', 'paramount network',
  ];

  static const List<String> generalSportsKeywords = [
    'sports', 'espn', 'espn2', 'espn3', 'espnu', 'espnews', 'fox sports',
    'fs1', 'fs2', 'cbs sports', 'cbsn', 'nbc sports', 'tnt', 'tbs', 'tru tv',
    'dazn', 'bein', 'bein sport', 'sky sports', 'sky sport', 'bt sport',
    'eurosport', 'eurosport 1', 'eurosport 2', 'sport tv', 'premium sport',
    'sport 1', 'sport 2', 'sport 3', 'sport 4', 'sport 5', 'tnt sport',
    'tnt sports', 'paramount', 'peacock', 'abc', 'cbs', 'nbc', 'fox',
    'usa network', 'golf channel', 'nfl network', 'nba tv', 'mlb network',
    'nhl network', 'tennis channel', 'olympic', 'sportsnet', 'tsn', 'rds',
    'cbc', 'ctv', 'kayo', 'fox footy', 'fox league', 'seven', 'nine',
    'willow', 'sky racing',
  ];

  static const Set<String> genericNetworks = {
    'fox', 'abc', 'cbs', 'nbc', 'cbc', 'ctv', 'seven', 'nine', 'paramount',
    'peacock',
  };

  static const List<String> sportsIndicators = [
    'sport', 'sports', 'fs1', 'fs2', 'espn', 'nfl', 'nba', 'mlb', 'nhl',
    'ufc', 'fight', 'game', 'league', 'pass', 'network', 'tv', 'stream',
    'live',
  ];

  static bool isNonSportsChannel(String channelName, String categoryName) {
    if (_nonSportsChannelKeywords.any(channelName.contains)) return true;
    final isNonSportsCategory = _nonSportsGroupKeywords.any(categoryName.contains);
    final isSportsCategory = _sportsCategoryIndicators.any(categoryName.contains);
    if (isNonSportsCategory && !isSportsCategory) return true;
    return false;
  }

  static bool matchesByLeagueKeywords(
    String league,
    String channelName,
    String category,
  ) {
    if (league.trim().isEmpty) return false;
    final key = leagueKey(league);
    final keywords = leagueKeywords[key] ?? [league.toLowerCase()];
    return keywords.any((kw) {
      final kwLower = kw.toLowerCase();
      if (genericNetworks.contains(kwLower)) {
        return (channelName.contains(kwLower) || category.contains(kwLower)) &&
            sportsIndicators.any(
              (i) => channelName.contains(i) || category.contains(i),
            );
      }
      return channelName.contains(kwLower) || category.contains(kwLower);
    });
  }

  static String leagueKey(String league) {
    final upper = league.trim().toUpperCase();
    switch (upper) {
      case 'ENG.1':
      case 'PREMIER LEAGUE':
      case 'EPL':
        return 'EPL';
      case 'ESP.1':
      case 'LALIGA':
        return 'LALIGA';
      case 'ITA.1':
      case 'SERIE A':
        return 'SERIEA';
      case 'GER.1':
      case 'BUNDESLIGA':
        return 'BUNDES';
      case 'FRA.1':
      case 'LIGUE 1':
        return 'LIGUE1';
      case 'USA.1':
      case 'MLS':
        return 'MLS';
      case 'ENGLISH-PREMIERSHIP':
      case 'ENGLISH PREMIERSHIP':
        return 'RUGBY';
      case 'COLLEGE-FOOTBALL':
      case 'COLLEGE FOOTBALL':
        return 'CFB';
      case 'MENS-COLLEGE-BASKETBALL':
      case 'NCAA BASKETBALL':
        return 'CBB';
      case 'ATP':
      case 'WTA':
        return 'TEN';
      case 'PGA':
      case 'PGATOUR':
        return 'GOLF';
      case 'F1':
      case 'FORMULA 1':
        return 'F1';
      default:
        return upper;
    }
  }

  static bool matchesGeneralSportsKeywords(String channelName, String category) {
    return generalSportsKeywords.any((kw) {
      if (genericNetworks.contains(kw)) {
        return (channelName.contains(kw) || category.contains(kw)) &&
            sportsIndicators.any(
              (i) => channelName.contains(i) || category.contains(i),
            );
      }
      return channelName.contains(kw) || category.contains(kw);
    });
  }

  static String detectRegion(IptvChannel channel) {
    final cn = channel.name.toLowerCase();
    final cat = (channel.group ?? '').toLowerCase();
    if (cn.contains('bbc') ||
        cn.contains('itv') ||
        cn.contains('channel 4') ||
        cn.contains('sky sports') ||
        cn.contains('bt sport') ||
        cn.contains('uk') ||
        cn.contains('british') ||
        cat.contains('uk') ||
        cat.contains('united kingdom')) {
      return 'UK';
    }
    if (cn.contains('cbc') ||
        cn.contains('tsn') ||
        cn.contains('sportsnet') ||
        cn.contains('canada') ||
        cn.contains('toronto') ||
        cat.contains('canada') ||
        cat.contains('canadian')) {
      return 'CA';
    }
    if (cn.contains('fox') ||
        cn.contains('espn') ||
        cn.contains('cbs') ||
        cn.contains('nbc') ||
        cn.contains('abc') ||
        cn.contains('nfl network') ||
        cn.contains('nba tv') ||
        cn.contains('mlb network') ||
        cn.contains('nhl network') ||
        cn.contains('us') ||
        cn.contains('american') ||
        cat.contains('us') ||
        cat.contains('usa')) {
      return 'US';
    }
    return 'Other';
  }
}
