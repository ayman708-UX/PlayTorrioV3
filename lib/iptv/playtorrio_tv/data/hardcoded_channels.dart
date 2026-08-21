import 'package:flutter/material.dart';

/// A "branded" channel that the user can pick from a curated grid.
/// `keywords` are case-insensitive substring matches against the stream name.
/// Any match wins, unless the name also contains a string in `exclude`.
class HardcodedChannel {
  final String id;
  final String name;
  final String short;
  final List<String> keywords;
  final List<Color> gradient;
  final List<String> exclude;
  const HardcodedChannel({
    required this.id,
    required this.name,
    required this.short,
    required this.keywords,
    required this.gradient,
    this.exclude = const [],
  });
}

class HardcodedChannels {
  static const _soccer = [Color(0xFF7C3AED), Color(0xFF22D3EE)];
  static const _usSport = [Color(0xFFEF4444), Color(0xFFF59E0B)];
  static const _wrestling = [Color(0xFFB91C1C), Color(0xFF1F2937)];
  static const _motor = [Color(0xFFDC2626), Color(0xFF111827)];
  static const _fight = [Color(0xFFF97316), Color(0xFF7C2D12)];
  static const _ukSport = [Color(0xFF1D4ED8), Color(0xFF22C55E)];
  static const _news = [Color(0xFF0EA5E9), Color(0xFF1E293B)];
  static const _movie = [Color(0xFFEC4899), Color(0xFF8B5CF6)];
  static const _kids = [Color(0xFFFBBF24), Color(0xFFF472B6)];
  static const _music = [Color(0xFF06B6D4), Color(0xFFA855F7)];
  static const _doc = [Color(0xFF14B8A6), Color(0xFF0F766E)];
  static const _ent = [Color(0xFFF59E0B), Color(0xFFDB2777)];
  static const _arabic = [Color(0xFF059669), Color(0xFF064E3B)];

  static const List<HardcodedChannel> all = [
    // ── Combat sports ──
    HardcodedChannel(id: 'ufc', name: 'UFC', short: 'UFC', gradient: _fight, keywords: [
      'ufc', 'ufc fight pass', 'ufc ppv', 'ufc on espn', 'ufc fight night',
      'ufc 3', 'ufc apex', 'ufc on abc',
    ]),
    HardcodedChannel(id: 'wwe', name: 'WWE', short: 'WWE', gradient: _wrestling, keywords: [
      'wwe', 'wwe network', 'wwe ppv', 'wwe raw', 'wwe smackdown', 'wwe nxt',
      'wwe premium', 'wrestlemania', 'summerslam', 'royal rumble',
      'money in the bank', 'survivor series',
    ]),
    HardcodedChannel(id: 'aew', name: 'AEW', short: 'AEW', gradient: _wrestling, keywords: [
      'aew', 'all elite wrestling', 'aew dynamite', 'aew rampage',
      'aew collision', 'aew revolution', 'aew double or nothing', 'aew full gear',
    ]),
    HardcodedChannel(id: 'boxing', name: 'Boxing', short: 'BOX', gradient: _fight, keywords: [
      'boxing', 'ppv box', 'fight night', 'fite tv', 'fite', 'matchroom',
      'top rank', 'premier boxing', 'pbc ', 'queensberry', 'espn boxing',
      'showtime boxing', 'boxnation', 'fight network', 'dazn boxing',
      'boxing nation', 'golden boy', 'wbo', 'wbc', 'ibf', 'wba',
      'world boxing', 'championship boxing', 'super middleweight', 'heavyweight',
      'sky sports boxing',
    ], exclude: ['box office', 'xbox', 'boxset', 'box set', 'music box', 'kids box']),
    HardcodedChannel(id: 'bellator', name: 'Bellator MMA', short: 'BLR', gradient: _fight, keywords: [
      'bellator', 'bellator mma', 'pfl ', 'pfl mma', 'professional fighters league',
    ]),
    HardcodedChannel(id: 'ppv_events', name: 'PPV Events', short: 'PPV', gradient: _fight, keywords: [
      ' ppv', 'ppv ', 'pay per view', 'pay-per-view',
    ]),
    HardcodedChannel(id: 'one_championship', name: 'ONE Championship', short: 'ONE', gradient: _fight, keywords: [
      'one championship', 'one fc', 'one mma', 'one martial arts',
    ]),
    // ── Motorsport ──
    HardcodedChannel(id: 'f1', name: 'Formula 1', short: 'F1', gradient: _motor, keywords: [
      'f1 tv', 'formula 1', 'formula one', 'sky f1', 'skysports f1',
      'sky sport f1', 'sky sports f1', 'ssf1', 'ss f1', 'espn f1', 'f1 race',
      'grand prix', 'gp race', 'f1 qualifying', 'formula 1 grand prix',
    ]),
    HardcodedChannel(id: 'motogp', name: 'MotoGP', short: 'GP', gradient: _motor, keywords: [
      'motogp', 'moto gp', 'moto-gp', 'moto2', 'moto3', 'motogp race',
    ]),
    HardcodedChannel(id: 'nascar', name: 'NASCAR', short: 'NSC', gradient: _motor, keywords: [
      'nascar', 'nascar cup', 'daytona 500', 'nascar xfinity',
    ]),
    HardcodedChannel(id: 'indycar', name: 'IndyCar', short: 'INDY', gradient: _motor, keywords: [
      'indycar', 'indy car', 'indy 500', 'indianapolis 500',
    ]),
    HardcodedChannel(id: 'wrc', name: 'WRC Rally', short: 'WRC', gradient: _motor, keywords: [
      'wrc', 'world rally', 'rallytv', 'rally tv', 'rally championship',
    ]),
    HardcodedChannel(id: 'superbike', name: 'Superbike / WSBK', short: 'WSBK', gradient: _motor, keywords: [
      'wsbk', 'superbike', 'world superbike', 'worldsbk',
    ]),
    // ── Soccer ──
    HardcodedChannel(id: 'bein_sports', name: 'beIN Sports', short: 'BEIN', gradient: _soccer, keywords: [
      'bein sport', 'bein sports', 'beinsports', 'bein ', 'bein 1', 'bein 2',
      'bein 3', 'bein hd', 'bein max', 'bein sports arabia', 'bein sport arabic',
    ]),
    HardcodedChannel(id: 'sky_sports', name: 'Sky Sports', short: 'SKY', gradient: _ukSport, keywords: [
      'sky sport', 'sky sports', 'skysports', 'sky sports main event',
      'sky sports premier league', 'sky sports football', 'sky sports action',
      'sky sports arena', 'sky sports cricket', 'sky sports golf', 'sky sports f1',
    ], exclude: ['sky sports news']),
    HardcodedChannel(id: 'tnt_sports', name: 'TNT Sports', short: 'TNT', gradient: _ukSport, keywords: [
      'tnt sport', 'tnt sports', 'bt sport', 'btsport', 'tnt sports 1',
      'tnt sports 2', 'tnt sports 3', 'tnt sports 4', 'bt sport 1', 'bt sport 2', 'bt sport 3',
    ]),
    HardcodedChannel(id: 'champions_league', name: 'Champions League', short: 'UCL', gradient: _soccer, keywords: [
      'champions league', 'uefa champions', 'ucl ', ' ucl ', 'uefa europa',
      'europa league', 'conference league', 'uecl', 'bein champions',
      'bein ucl', 'tnt sports ucl', 'sky sports ucl', 'cbs sports ucl',
      'paramount+ ucl', 'dazn champions', 'canal+ champions',
    ]),
    HardcodedChannel(id: 'premier_league', name: 'Premier League', short: 'EPL', gradient: _soccer, keywords: [
      'premier league', 'epl ', 'barclays premier', ' bpl ', 'sky sports pl',
      'bein epl', 'nbc premier league', 'peacock premier league',
      'manutd', 'man city', 'arsenal fc',
    ]),
    HardcodedChannel(id: 'la_liga', name: 'La Liga', short: 'LL', gradient: _soccer, keywords: [
      'laliga', 'la liga', 'movistar laliga', 'laliga tv', 'laliga ea sports',
    ]),
    HardcodedChannel(id: 'serie_a', name: 'Serie A', short: 'SA', gradient: _soccer, keywords: [
      'serie a', 'dazn italia', 'sky calcio', 'calcio', 'italian football', 'serie a tim',
    ]),
    HardcodedChannel(id: 'bundesliga', name: 'Bundesliga', short: 'BL', gradient: _soccer, keywords: [
      'bundesliga', 'sky bundesliga', 'dazn bundes', 'german football', 'bundesliga 2',
    ]),
    HardcodedChannel(id: 'ligue_1', name: 'Ligue 1', short: 'L1', gradient: _soccer, keywords: [
      'ligue 1', 'ligue1', 'canal+ sport', 'canal plus sport', 'rmc sport',
      'prime video ligue', 'french football', 'ligue 2', 'dazn ligue',
    ]),
    HardcodedChannel(id: 'mls', name: 'MLS', short: 'MLS', gradient: _soccer, keywords: [
      ' mls', 'mls ', 'major league soccer', 'apple mls', 'mls season pass', 'mls next',
    ]),
    HardcodedChannel(id: 'world_cup', name: 'World Cup', short: 'WC', gradient: _soccer, keywords: [
      'world cup', 'fifa world', 'fifa+', 'fifa plus', 'qatar 2022', 'wc 2026',
    ]),
    HardcodedChannel(id: 'eredivisie', name: 'Eredivisie', short: 'ERE', gradient: _soccer, keywords: [
      'eredivisie', 'dutch football', 'netherlands football',
    ]),
    HardcodedChannel(id: 'primeira_liga', name: 'Primeira Liga', short: 'PL', gradient: _soccer, keywords: [
      'primeira liga', 'liga portugal', 'portuguese football', 'liga nos', 'sport tv portugal',
    ]),
    HardcodedChannel(id: 'super_lig', name: 'Süper Lig', short: 'SL', gradient: _soccer, keywords: [
      'super lig', 'süper lig', 'turkish football', 'bein turkey',
    ]),
    HardcodedChannel(id: 'african_football', name: 'African Football', short: 'CAF', gradient: _soccer, keywords: [
      'afcon', 'africa cup', 'caf champions', 'caf cl', 'caf confederations', 'supersport africa',
    ]),
    HardcodedChannel(id: 'copa_libertadores', name: 'Copa Libertadores', short: 'LIB', gradient: _soccer, keywords: [
      'copa libertadores', 'libertadores', 'copa sudamericana', 'conmebol',
    ]),
    HardcodedChannel(id: 'beout_q', name: 'SuperSport', short: 'SS', gradient: _soccer, keywords: [
      'supersport', 'super sport', 'dstv sport',
    ]),
    // ── US sports ──
    HardcodedChannel(id: 'espn', name: 'ESPN', short: 'ESPN', gradient: _usSport, keywords: [
      'espn', 'espn2', 'espn 2', 'espnews', 'espn+', 'espn plus',
      'espn deportes', 'espn u', 'espnu',
    ]),
    HardcodedChannel(id: 'fox_sports', name: 'Fox Sports', short: 'FOX', gradient: _usSport, keywords: [
      'fox sport', 'fox sports', 'fs1', 'fs2', 'fox soccer', 'fox deportes',
    ]),
    HardcodedChannel(id: 'nbc_sports', name: 'NBC Sports', short: 'NBC', gradient: _usSport, keywords: [
      'nbc sport', 'nbc sports', 'nbcsn', 'peacock sport', 'nbc gold',
    ]),
    HardcodedChannel(id: 'cbs_sports', name: 'CBS Sports', short: 'CBS', gradient: _usSport, keywords: [
      'cbs sport', 'cbs sports', 'paramount sport', 'cbs sports hq',
    ]),
    HardcodedChannel(id: 'tnt_us', name: 'TNT (USA)', short: 'TNT', gradient: _usSport, keywords: [
      'tnt usa', 'tnt us ', 'tnt hd usa', 'max sports',
    ]),
    HardcodedChannel(id: 'nba', name: 'NBA', short: 'NBA', gradient: _usSport, keywords: [
      'nba ', 'nba tv', 'nba league pass', 'nba hd', 'nba g league',
    ]),
    HardcodedChannel(id: 'nfl', name: 'NFL', short: 'NFL', gradient: _usSport, keywords: [
      'nfl ', 'nfl network', 'nfl hd', 'nfl sunday ticket', 'nfl game pass',
    ]),
    HardcodedChannel(id: 'nfl_redzone', name: 'NFL RedZone', short: 'RZ', gradient: _usSport, keywords: [
      'redzone', 'red zone',
    ]),
    HardcodedChannel(id: 'nhl', name: 'NHL', short: 'NHL', gradient: _usSport, keywords: [
      'nhl ', 'nhl network', 'nhl hd', 'nhl tv', 'hockey night',
    ]),
    HardcodedChannel(id: 'mlb', name: 'MLB', short: 'MLB', gradient: _usSport, keywords: [
      'mlb ', 'mlb network', 'mlb hd', 'mlb tv', 'mlb extra innings',
    ]),
    HardcodedChannel(id: 'bally_sports', name: 'Bally Sports', short: 'BSN', gradient: _usSport, keywords: [
      'bally sport', 'bally sports', 'fanduel sports network',
    ]),
    HardcodedChannel(id: 'tennis_channel', name: 'Tennis Channel', short: 'TEN', gradient: _soccer, keywords: [
      'tennis channel', 'tennis hd', 'atp tennis', 'wta tennis', 'tennis tv',
      'wimbledon', 'us open tennis', 'french open', 'australian open',
      'roland garros', 'atp tour', 'wta tour',
    ]),
    HardcodedChannel(id: 'golf_channel', name: 'Golf Channel', short: 'GLF', gradient: _soccer, keywords: [
      'golf channel', 'golf tv', 'sky golf', 'pga tour', 'masters golf',
      'the open golf', 'ryder cup', 'golf live',
    ]),
    HardcodedChannel(id: 'amazon_prime_sport', name: 'Prime Video Sport', short: 'PVS', gradient: _usSport, keywords: [
      'prime video sport', 'prime sport', 'amazon sport', 'amazon prime sport',
      'prime video nfl', 'prime video ucl', 'prime video ligue',
    ]),
    HardcodedChannel(id: 'cricket', name: 'Cricket', short: 'CRK', gradient: _soccer, keywords: [
      'cricket', 'star sports cricket', 'sky sports cricket', 'willow cricket',
      'willow tv', 'sony ten', 'sony six cricket', 'espn cricinfo',
      'icc cricket', 'test match', 'odi ', 't20 ', 'ipl ',
      'indian premier league', 'big bash', 'cpl cricket', 'the hundred', 'county cricket',
    ]),
    HardcodedChannel(id: 'dazn', name: 'DAZN', short: 'DAZN', gradient: _fight, keywords: ['dazn']),
    HardcodedChannel(id: 'eurosport', name: 'Eurosport', short: 'EURO', gradient: _soccer, keywords: [
      'eurosport', 'eurosport 1', 'eurosport 2', 'discovery+ sport', 'gcn+ ', 'cycling tv',
    ]),
    HardcodedChannel(id: 'axs_wrestling', name: 'Wrestling AXS', short: 'AXS', gradient: _wrestling, keywords: [
      'axs tv', 'njpw', 'new japan pro', 'impact wrestling', 'tna ',
    ]),
    HardcodedChannel(id: 'sport_tv', name: 'Sport TV (general)', short: 'STV', gradient: _soccer, keywords: [
      'sport tv', 'sportv', 'sport channel', 'sports channel',
    ]),
    // ── News ──
    HardcodedChannel(id: 'cnn', name: 'CNN', short: 'CNN', gradient: _news, keywords: [
      'cnn', 'cnn international', 'cnn hd',
    ]),
    HardcodedChannel(id: 'bbc_news', name: 'BBC News', short: 'BBC', gradient: _news, keywords: [
      'bbc news', 'bbc world', 'bbc world news',
    ]),
    HardcodedChannel(id: 'fox_news', name: 'Fox News', short: 'FXN', gradient: _news, keywords: [
      'fox news', 'fox business',
    ]),
    HardcodedChannel(id: 'msnbc', name: 'MSNBC', short: 'MSN', gradient: _news, keywords: ['msnbc']),
    HardcodedChannel(id: 'sky_news', name: 'Sky News', short: 'SKN', gradient: _news, keywords: [
      'sky news', 'sky news arabia',
    ]),
    HardcodedChannel(id: 'al_jazeera', name: 'Al Jazeera', short: 'AJ', gradient: _news, keywords: [
      'al jazeera', 'aljazeera', 'jazeera', 'al jazeera english', 'al jazeera arabic',
    ]),
    HardcodedChannel(id: 'cnbc', name: 'CNBC', short: 'CNBC', gradient: _news, keywords: [
      'cnbc', 'cnbc international', 'cnbc arabic',
    ]),
    HardcodedChannel(id: 'bloomberg', name: 'Bloomberg', short: 'BLM', gradient: _news, keywords: [
      'bloomberg', 'bloomberg tv',
    ]),
    HardcodedChannel(id: 'france24', name: 'France 24', short: 'F24', gradient: _news, keywords: [
      'france 24', 'france24',
    ]),
    HardcodedChannel(id: 'dw_news', name: 'DW News', short: 'DW', gradient: _news, keywords: [
      'dw news', 'deutsche welle', ' dw ',
    ]),
    HardcodedChannel(id: 'euronews', name: 'Euronews', short: 'EN', gradient: _news, keywords: [
      'euronews', 'euro news',
    ]),
    HardcodedChannel(id: 'rt_news', name: 'RT News', short: 'RT', gradient: _news, keywords: [
      'rt news', 'russia today',
    ]),
    HardcodedChannel(id: 'trt_world', name: 'TRT World', short: 'TRT', gradient: _news, keywords: [
      'trt world', 'trt haber',
    ]),
    HardcodedChannel(id: 'sky_sports_news', name: 'Sky Sports News', short: 'SSN', gradient: _news, keywords: [
      'sky sports news', 'ssn ',
    ]),
    // ── UK general ──
    HardcodedChannel(id: 'bbc_one', name: 'BBC One', short: 'BBC1', gradient: _ukSport, keywords: [
      'bbc one', 'bbc1', 'bbc 1',
    ]),
    HardcodedChannel(id: 'bbc_two', name: 'BBC Two', short: 'BBC2', gradient: _ukSport, keywords: [
      'bbc two', 'bbc2', 'bbc 2',
    ]),
    HardcodedChannel(id: 'itv', name: 'ITV', short: 'ITV', gradient: _ukSport, keywords: [
      'itv1', 'itv 1', 'itv2', 'itv 2', 'itv3', 'itv 3', 'itv4', 'itv 4', 'itv hd', 'itvx',
    ]),
    HardcodedChannel(id: 'channel_4', name: 'Channel 4', short: 'CH4', gradient: _ukSport, keywords: [
      'channel 4', 'channel4', 'ch4 ', 'e4 ', ' e4', 'more4',
    ]),
    HardcodedChannel(id: 'channel_5', name: 'Channel 5', short: 'CH5', gradient: _ukSport, keywords: [
      'channel 5', 'channel5', 'ch5 ', '5star', '5 star', '5usa',
    ]),
    // ── Movies / premium ──
    HardcodedChannel(id: 'hbo', name: 'HBO', short: 'HBO', gradient: _movie, keywords: [
      'hbo', 'hbo max', 'max originals', 'hbo signature', 'hbo family',
    ]),
    HardcodedChannel(id: 'showtime', name: 'Showtime', short: 'SHO', gradient: _movie, keywords: [
      'showtime', 'showtime 2',
    ]),
    HardcodedChannel(id: 'starz', name: 'Starz', short: 'STZ', gradient: _movie, keywords: [
      'starz', 'starz encore',
    ]),
    HardcodedChannel(id: 'cinemax', name: 'Cinemax', short: 'CMX', gradient: _movie, keywords: [
      'cinemax', 'max prime',
    ]),
    HardcodedChannel(id: 'paramount', name: 'Paramount', short: 'PAR', gradient: _movie, keywords: [
      'paramount network', 'paramount+', 'paramount plus', 'paramount channel',
    ]),
    HardcodedChannel(id: 'amc', name: 'AMC', short: 'AMC', gradient: _movie, keywords: [
      ' amc ', 'amc hd', 'amc usa', 'amc network', 'amc+',
    ]),
    HardcodedChannel(id: 'fx', name: 'FX', short: 'FX', gradient: _movie, keywords: [
      ' fx ', 'fx hd', 'fxx', 'fx usa', 'fx movie',
    ]),
    HardcodedChannel(id: 'tnt_drama', name: 'TBS / TNT Drama', short: 'TBS', gradient: _movie, keywords: [
      'tbs ', 'tbs hd', 'tnt drama',
    ]),
    HardcodedChannel(id: 'usa_network', name: 'USA Network', short: 'USA', gradient: _movie, keywords: [
      'usa network', ' usa hd', 'usa channel',
    ]),
    HardcodedChannel(id: 'syfy', name: 'Syfy', short: 'SYFY', gradient: _movie, keywords: [
      'syfy', 'sci fi', 'sci-fi',
    ]),
    HardcodedChannel(id: 'lifetime', name: 'Lifetime', short: 'LIFE', gradient: _movie, keywords: [
      'lifetime', 'lifetime movie',
    ]),
    HardcodedChannel(id: 'hallmark', name: 'Hallmark', short: 'HLM', gradient: _movie, keywords: [
      'hallmark', 'hallmark channel', 'hallmark movies',
    ]),
    HardcodedChannel(id: 'tcm', name: 'TCM', short: 'TCM', gradient: _movie, keywords: [
      'tcm ', 'turner classic',
    ]),
    HardcodedChannel(id: 'sky_cinema', name: 'Sky Cinema', short: 'SCIN', gradient: _movie, keywords: [
      'sky cinema', 'sky movies', 'sky cinema premiere', 'sky cinema action',
      'sky cinema comedy', 'sky cinema drama',
    ]),
    HardcodedChannel(id: 'osn_movies', name: 'OSN Movies', short: 'OSNM', gradient: _movie, keywords: [
      'osn movies', 'osn cinema', 'osn series', 'osn streaming',
    ]),
    HardcodedChannel(id: 'netflix', name: 'Netflix', short: 'NF', gradient: _movie, keywords: ['netflix']),
    HardcodedChannel(id: 'apple_tv', name: 'Apple TV+', short: 'ATV', gradient: _movie, keywords: [
      'apple tv', 'apple tv+', 'appletv',
    ]),
    // ── Documentary ──
    HardcodedChannel(id: 'discovery', name: 'Discovery', short: 'DISC', gradient: _doc, keywords: [
      'discovery', 'discovery+', 'discovery channel',
    ], exclude: ['kids']),
    HardcodedChannel(id: 'history', name: 'History', short: 'HIST', gradient: _doc, keywords: [
      'history channel', 'history hd', 'history us', 'history uk', ' hist ',
    ]),
    HardcodedChannel(id: 'nat_geo', name: 'Nat Geo', short: 'NATGEO', gradient: _doc, keywords: [
      'national geographic', 'nat geo', 'natgeo', 'nat-geo', 'nat geo wild',
    ]),
    HardcodedChannel(id: 'animal_planet', name: 'Animal Planet', short: 'AP', gradient: _doc, keywords: [
      'animal planet',
    ]),
    HardcodedChannel(id: 'tlc', name: 'TLC', short: 'TLC', gradient: _doc, keywords: ['tlc ']),
    HardcodedChannel(id: 'food_network', name: 'Food Network', short: 'FOOD', gradient: _doc, keywords: [
      'food network', 'food channel',
    ]),
    HardcodedChannel(id: 'hgtv', name: 'HGTV', short: 'HGTV', gradient: _doc, keywords: ['hgtv']),
    HardcodedChannel(id: 'investigation', name: 'ID', short: 'ID', gradient: _doc, keywords: [
      'investigation discovery', ' id channel', ' id hd', 'id usa',
    ]),
    HardcodedChannel(id: 'vice', name: 'Vice / Vice TV', short: 'VICE', gradient: _doc, keywords: [
      'vice tv', 'vicetv', 'vice channel',
    ]),
    // ── Kids ──
    HardcodedChannel(id: 'cartoon_network', name: 'Cartoon Network', short: 'CN', gradient: _kids, keywords: [
      'cartoon network', 'cartoonnetwork', ' cn hd',
    ]),
    HardcodedChannel(id: 'disney', name: 'Disney', short: 'DSN', gradient: _kids, keywords: [
      'disney channel', 'disney hd', 'disney xd', 'disney junior', 'disney jr',
    ], exclude: ['disney+', 'disney plus']),
    HardcodedChannel(id: 'nickelodeon', name: 'Nickelodeon', short: 'NICK', gradient: _kids, keywords: [
      'nickelodeon', 'nick jr', 'nick hd', 'nicktoons', 'nick ',
    ]),
    HardcodedChannel(id: 'boomerang', name: 'Boomerang', short: 'BOOM', gradient: _kids, keywords: ['boomerang']),
    HardcodedChannel(id: 'pbs_kids', name: 'PBS Kids', short: 'PBS', gradient: _kids, keywords: [
      'pbs kids', 'pbs hd', ' pbs ',
    ]),
    HardcodedChannel(id: 'baby_tv', name: 'Baby TV', short: 'BTV', gradient: _kids, keywords: [
      'baby tv', 'baby channel',
    ]),
    HardcodedChannel(id: 'spacetoon', name: 'Spacetoon', short: 'SPC', gradient: _kids, keywords: ['spacetoon']),
    // ── Music ──
    HardcodedChannel(id: 'mtv', name: 'MTV', short: 'MTV', gradient: _music, keywords: [
      ' mtv ', 'mtv hd', 'mtv usa', 'mtv uk', 'mtv live', 'mtv 80s',
      'mtv 90s', 'mtv hits', 'mtv music',
    ]),
    HardcodedChannel(id: 'vh1', name: 'VH1', short: 'VH1', gradient: _music, keywords: ['vh1', 'vh-1']),
    HardcodedChannel(id: 'bet', name: 'BET', short: 'BET', gradient: _music, keywords: [
      'bet ', 'bet hd', 'bet hip', 'bet usa',
    ]),
    HardcodedChannel(id: 'mbc_masr', name: 'MBC Masr', short: 'MBM', gradient: _arabic, keywords: [
      'mbc masr', 'mbc مصر',
    ]),
    // ── Comedy ──
    HardcodedChannel(id: 'comedy_central', name: 'Comedy Central', short: 'CC', gradient: _ent, keywords: [
      'comedy central', 'comedy central hd',
    ]),
    HardcodedChannel(id: 'adult_swim', name: 'Adult Swim', short: 'AS', gradient: _ent, keywords: ['adult swim']),
    // ── Spanish / Latin ──
    HardcodedChannel(id: 'telemundo', name: 'Telemundo', short: 'TLM', gradient: _ent, keywords: ['telemundo']),
    HardcodedChannel(id: 'univision', name: 'Univision', short: 'UNI', gradient: _ent, keywords: ['univision', 'unimas']),
    HardcodedChannel(id: 'tudn', name: 'TUDN', short: 'TUDN', gradient: _ent, keywords: ['tudn']),
    // ── Arabic ──
    HardcodedChannel(id: 'mbc', name: 'MBC', short: 'MBC', gradient: _arabic, keywords: [
      'mbc1', 'mbc 1', 'mbc2', 'mbc 2', 'mbc3', 'mbc 3', 'mbc4', 'mbc 4',
      'mbc action', 'mbc max', 'mbc drama', 'mbc bollywood', 'mbc persia',
    ]),
    HardcodedChannel(id: 'rotana', name: 'Rotana', short: 'ROT', gradient: _arabic, keywords: [
      'rotana', 'rotana cinema', 'rotana khalijiah', 'rotana music', 'rotana klassik',
    ]),
    HardcodedChannel(id: 'osn', name: 'OSN', short: 'OSN', gradient: _arabic, keywords: [
      'osn', 'osn hd', 'osn yahala', 'osn living',
    ]),
    HardcodedChannel(id: 'abu_dhabi', name: 'Abu Dhabi TV', short: 'ADTV', gradient: _arabic, keywords: [
      'abu dhabi tv', 'ad sport', 'ad sports', 'abu dhabi sport',
    ]),
    HardcodedChannel(id: 'dubai_tv', name: 'Dubai TV', short: 'DXB', gradient: _arabic, keywords: [
      'dubai tv', 'dubai one', 'dubai sport',
    ]),
    HardcodedChannel(id: 'saudi_tv', name: 'Saudi TV', short: 'STV', gradient: _arabic, keywords: [
      'saudi tv', 'ksa sport', 'ksa sports', 'saudi sport',
    ]),
    HardcodedChannel(id: 'alarabiya', name: 'Al Arabiya', short: 'ARB', gradient: _news, keywords: [
      'al arabiya', 'alarabiya', 'arabiya',
    ]),
    HardcodedChannel(id: 'almajd', name: 'Al Majd', short: 'MAJ', gradient: _arabic, keywords: [
      'al majd', 'almajd', 'majd quran', 'majd kids',
    ]),
    // ── Indian ──
    HardcodedChannel(id: 'star_plus', name: 'Star Plus', short: 'STR', gradient: _ent, keywords: [
      'star plus', 'star+', 'star sports india', 'star sports 1', 'star sports 2', 'star gold',
    ]),
    HardcodedChannel(id: 'zee_tv', name: 'Zee TV', short: 'ZEE', gradient: _ent, keywords: [
      'zee tv', 'zee cinema', 'zee anmol', 'zee news', 'zee entertainment',
    ]),
    HardcodedChannel(id: 'sony_india', name: 'Sony (India)', short: 'SNY', gradient: _ent, keywords: [
      'sony tv', 'sony max', 'sony sab', 'sony six', 'sony pix', 'sony ten', 'sony liv',
    ]),
    HardcodedChannel(id: 'colors', name: 'Colors', short: 'CLR', gradient: _ent, keywords: [
      'colors tv', 'colors hd', 'colors cineplex', 'colors rishtey',
    ]),
    HardcodedChannel(id: 'sun_tv', name: 'Sun TV', short: 'SUN', gradient: _ent, keywords: [
      'sun tv', 'sun news', 'sun music', 'surya tv', 'kiran tv',
    ]),
    HardcodedChannel(id: 'aaj_tak', name: 'Aaj Tak / India Today', short: 'AAJ', gradient: _news, keywords: [
      'aaj tak', 'india today', 'india news',
    ]),
  ];

  static HardcodedChannel? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// True when [name] contains any [keywords] entry AND does NOT contain
  /// any [exclude] entry. Case-insensitive substring matching.
  static bool matches(
    String name,
    List<String> keywords, [
    List<String> exclude = const [],
  ]) {
    final lower = name.toLowerCase();
    for (final ex in exclude) {
      if (lower.contains(ex)) return false;
    }
    for (final k in keywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }
}
