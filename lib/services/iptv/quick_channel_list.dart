import '../../models/iptv/iptv_models.dart';

/// A curated "quick channel" — a logical TV brand that is resolved against the
/// user's actual playlists by name/alias matching.
class QuickChannel {
  final String displayName;
  final List<String> aliases;
  final List<String> regions;
  final List<String> tags;

  const QuickChannel(
    this.displayName,
    this.aliases,
    this.regions,
    this.tags,
  );
}

/// Port of `QuickChannelList.kt` — the curated catalog + matching logic.
class QuickChannelList {
  static final Set<String> _pinnedNames = <String>{};

  static List<QuickChannel> get all {
    final pinned = _pinnedNames
        .map((name) => _default.firstWhere(
              (c) => c.displayName == name,
              orElse: () => QuickChannel(name, [name], const [], const []),
            ))
        .toList();
    final rest = _default
        .where((c) => !_pinnedNames.contains(c.displayName))
        .toList();
    return [...pinned, ...rest];
  }

  static bool isPinned(String displayName) =>
      _pinnedNames.contains(displayName);

  static void togglePin(String displayName) {
    if (!_pinnedNames.add(displayName)) {
      _pinnedNames.remove(displayName);
    }
  }

  static void unpin(String displayName) {
    _pinnedNames.remove(displayName);
  }

  static const _regionUs = ['us', 'usa', 'united states'];
  static const _regionCa = ['ca', 'canada', 'canadian', 'canadien', 'canadiens'];
  static const _regionUk = ['uk', 'united kingdom', 'britain', 'british', 'england'];

  static const _regionTokensByDisplayName = <String, List<String>>{
    'US Channels': _regionUs,
    'CA Channels': _regionCa,
    'UK Channels': _regionUk,
  };

  static bool matches(QuickChannel quickChannel, IptvChannel channel) {
    final regionTokens = _regionTokensByDisplayName[quickChannel.displayName];
    if (regionTokens != null) {
      final name = channel.name.toLowerCase();
      final group = (channel.group ?? '').toLowerCase();
      return regionTokens.any((token) {
        final pattern = token.length <= 3
            ? RegExp('\\b$token\\b', caseSensitive: false)
            : RegExp(token, caseSensitive: false);
        return pattern.hasMatch(name) || pattern.hasMatch(group);
      });
    }
    final name = channel.name.toLowerCase();
    return name.contains(quickChannel.displayName.toLowerCase()) ||
        quickChannel.aliases.any(
          (alias) => name.contains(alias.toLowerCase()),
        );
  }

  static const List<QuickChannel> _default = [
    // ── 0. REGION SUB-CHANNEL BUNDLES ──────────────────────────────
    QuickChannel('US Channels', ['us', 'usa', 'united states', 'american'], ['US'], ['region']),
    QuickChannel('CA Channels', ['ca', 'canada', 'canadian', 'canadien', 'canadiens'], ['CA'], ['region']),
    QuickChannel('UK Channels', ['uk', 'united kingdom', 'britain', 'british', 'england'], ['UK'], ['region']),

    // ── 1. NEWS ────────────────────────────────────────────────────
    QuickChannel('CNN', ['CNN', 'CNN US', 'CNN USA', 'CNN International', 'CNNI'], ['US'], ['news']),
    QuickChannel('Fox News', ['Fox News', 'Fox News Channel', 'FNC'], ['US'], ['news']),
    QuickChannel('MSNBC', ['MSNBC', 'MSNBC US'], ['US'], ['news']),
    QuickChannel('BBC News', ['BBC News', 'BBC World News', 'BBC News UK'], ['UK', 'US'], ['news']),
    QuickChannel('Sky News & World', ['Sky News', 'Sky News UK', 'Al Jazeera', 'Al Jazeera English', 'CNBC', 'CNBC World', 'Bloomberg', 'Bloomberg TV', 'Bloomberg Television', 'France 24', 'DW', 'Deutsche Welle', 'Euronews', 'RT News', 'RT International', 'Russia Today', 'TRT World', 'Sky Sports News'], ['UK', 'US', 'CA', 'EU'], ['news']),
    QuickChannel('Canadian News', ['CBC News', 'CBC News Network', 'CBCNN', 'CTV News', 'CTV News Channel', 'Global News', 'CP24'], ['CA'], ['news']),
    QuickChannel('Newsmax', ['Newsmax', 'Newsmax TV', 'Newsmax HD'], ['US'], ['news']),
    QuickChannel('NewsNation', ['NewsNation', 'News Nation', 'NewsNation Now'], ['US'], ['news']),
    QuickChannel('Fox Business', ['Fox Business', 'Fox Business Network', 'FBN'], ['US'], ['news']),
    QuickChannel('The Weather Channel', ['The Weather Channel', 'Weather Channel', 'TWC', 'WeatherNation', 'Weather Nation'], ['US', 'CA'], ['news']),
    QuickChannel('Court TV', ['Court TV', 'CourtTV', 'Court TV LIVE', 'Court TV Live'], ['US'], ['news', 'entertainment']),
    QuickChannel('OAN', ['OAN', 'One America News', 'One America News Network', 'OAN Plus'], ['US'], ['news']),
    QuickChannel('Real America\'s Voice', ['Real America\'s Voice', 'Real America\'s Voice News', 'RAV'], ['US'], ['news']),
    QuickChannel('Newsy', ['Newsy', 'Scripps News', 'Scripps News International'], ['US'], ['news']),
    QuickChannel('Cheddar', ['Cheddar', 'Cheddar News'], ['US'], ['news']),
    QuickChannel('ABC News Live', ['ABC News Live', 'ABC News 24', 'ABC News Direct'], ['US'], ['news']),
    QuickChannel('CBS News 24/7', ['CBS News 24/7', 'CBS News Now', 'CBS News Streaming'], ['US'], ['news']),
    QuickChannel('NBC News Now', ['NBC News Now', 'NBC News NOW', 'NBC News 24/7'], ['US'], ['news']),
    QuickChannel('Fox Weather', ['Fox Weather', 'FOX Weather', 'Fox Weather Network'], ['US'], ['news']),
    QuickChannel('CBN News', ['CBN News', 'CBN News Channel', 'CBN'], ['US'], ['news']),
    QuickChannel('i24 News', ['i24 News', 'i24NEWS', 'i24 English'], ['US', 'EU'], ['news']),
    QuickChannel('CGTN', ['CGTN', 'CGTN America', 'CGTN English', 'China Global Television Network'], ['US', 'EU', 'CA'], ['news']),
    QuickChannel('NHK World Japan', ['NHK World', 'NHK World Japan', 'NHK WORLD-JAPAN'], ['US', 'CA', 'EU'], ['news']),
    QuickChannel('Dubai One', ['Dubai One', 'Dubai TV', 'Dubai One English'], ['EU'], ['news']),
    QuickChannel('GB News', ['GB News', 'GB News UK'], ['UK'], ['news']),
    QuickChannel('TalkTV', ['TalkTV', 'Talk TV', 'Talk TV UK'], ['UK'], ['news']),
    QuickChannel('LBC', ['LBC', 'LBC News', 'LBC UK'], ['UK'], ['news']),
    QuickChannel('STV News', ['STV News', 'STV', 'STV Scotland', 'STV News Scotland'], ['UK'], ['news']),
    QuickChannel('Sky News Australia', ['Sky News Australia', 'Sky News AU', 'Sky News Australia HD'], ['AU'], ['news']),
    QuickChannel('Fox News Australia', ['Fox News Australia', 'FOX News Australia', 'FNA'], ['AU'], ['news']),
    QuickChannel('ABC News Australia', ['ABC News Australia', 'ABC News 24', 'ABC Australia', 'ABC News AU'], ['AU'], ['news']),

    // ── 2. US SPORTS & REGIONAL ────────────────────────────────────
    QuickChannel('ESPN', ['ESPN', 'ESPN US', 'ESPN 2', 'ESPN2', 'ESPN News', 'ESPNNews', 'ESPN U', 'ESPNU', 'SEC Network', 'SECN', 'ACC Network', 'ACCN'], ['US'], ['sports']),
    QuickChannel('Fox Sports', ['FS1', 'Fox Sports 1', 'FS2', 'Fox Sports 2', 'Big Ten Network', 'BTN', 'NBC Sports'], ['US'], ['sports']),
    QuickChannel('CBS Sports', ['CBS Sports Network', 'CBSSN'], ['US'], ['sports']),
    QuickChannel('US League Networks', ['NFL Network', 'NFLN', 'NFL RedZone', 'RedZone', 'NBA TV', 'NBATV', 'MLB Network', 'MLBN', 'Golf Channel', 'Tennis Channel', 'Olympic Channel', 'NBA', 'NFL', 'NHL', 'MLB', 'Tennis', 'Golf', 'Bally Sports', 'FanDuel Sports', 'Prime Video Sport', 'Cricket'], ['US'], ['sports']),
    QuickChannel('NHL Network', ['NHL Network', 'NHLN', 'NHL Network US', 'NHL Network Canada'], ['US', 'CA'], ['sports']),
    QuickChannel('Fox Soccer Plus', ['Fox Soccer Plus', 'FSP', 'Fox Soccer'], ['US'], ['sports']),
    QuickChannel('GolTV', ['GolTV', 'GolTV US', 'Gol TV'], ['US'], ['sports']),
    QuickChannel('Willow Cricket', ['Willow', 'Willow Cricket', 'Willow HD'], ['US', 'CA'], ['sports']),
    QuickChannel('TVG', ['TVG', 'TVG Network', 'TwinSpires TVG'], ['US'], ['sports']),
    QuickChannel('Stadium', ['Stadium', 'Stadium Network', 'Stadium Sports'], ['US'], ['sports']),
    QuickChannel('Pac-12 Networks', ['Pac-12', 'Pac-12 Network', 'Pac-12 Networks', 'Pac12'], ['US'], ['sports']),
    QuickChannel('Fight Network', ['Fight Network', 'The Fight Network', 'Fight TV'], ['CA', 'US'], ['sports']),
    QuickChannel('ESPN Deportes', ['ESPN Deportes', 'ESPN Deportes US', 'ESPN2 Deportes'], ['US', 'LA'], ['sports']),
    QuickChannel('Fox Deportes', ['Fox Deportes', 'FOX Deportes', 'Fox Sports Deportes'], ['US', 'LA'], ['sports']),
    QuickChannel('TUDN', ['TUDN', 'TUDN USA', 'Univision Deportes', 'Univision Deportes Network'], ['US', 'LA'], ['sports']),
    QuickChannel('US Regional Sports', ['YES Network', 'NESN', 'MASN', 'MSG Network', 'MSG', 'Marquee Sports Network', 'NBC Sports Bay Area', 'NBCS Bay Area', 'NBCSBA', 'NBC Sports California', 'NBCS California', 'NBCSCA'], ['US', 'bay-area'], ['sports', 'regional']),

    // ── 3. INTERNATIONAL SPORTS ─────────────────────────────────────
    QuickChannel('Sky Sports', ['Sky Sports', 'Sky Sports Main Event', 'Sky Sports Premier League', 'Sky Sports PL', 'Sky Sports Football', 'Sky Sports Cricket', 'Sky Sports Golf', 'Sky Sports F1', 'Sky Sports Action'], ['UK'], ['sports']),
    QuickChannel('TNT Sports', ['TNT Sports', 'TNT Sports 1', 'TNT Sports 2', 'TNT Sports 3', 'TNT Sports 4', 'BT Sport', 'BT Sport 1', 'BT Sport 2', 'BT Sport 3', 'BT Sport ESPN'], ['UK'], ['sports']),
    QuickChannel('Canadian Sports', ['TSN', 'TSN 1', 'TSN1', 'TSN 2', 'TSN2', 'TSN 3', 'TSN3', 'TSN 4', 'TSN4', 'TSN 5', 'TSN5', 'Sportsnet', 'Sportsnet 360', 'SN360', 'Sportsnet ONE', 'SN1', 'Sportsnet Ontario', 'Sportsnet East', 'Sportsnet West', 'Sportsnet Pacific', 'RDS', 'RDS 2', 'RDS2', 'CBC Sports'], ['CA'], ['sports']),
    QuickChannel('Global Sports Networks', ['DAZN', 'DAZN 1', 'DAZN 2', 'DAZN 1 UK', 'DAZN 2 UK', 'Eurosport', 'Eurosport 1', 'Eurosport 2', 'beIN Sports', 'beIN Sports 1', 'beIN Sports 2', 'beIN', 'Sport TV', 'Sport TV 1', 'Sport TV 2', 'Sport TV 3'], ['US', 'UK', 'CA', 'EU'], ['sports']),
    QuickChannel('Combat Sports', ['UFC', 'UFC Fight Night', 'UFC PPV', 'WWE', 'WWE Raw', 'WWE SmackDown', 'AEW', 'AEW Dynamite', 'Boxing', 'Bellator', 'PFL', 'Bellator/PFL', 'PPV Events', 'PPV', 'ONE Championship', 'ONE FC', 'AXS Wrestling'], ['US', 'UK', 'CA', 'EU'], ['sports']),
    QuickChannel('Motorsport', ['F1', 'Formula 1', 'Formula One', 'MotoGP', 'NASCAR', 'IndyCar', 'Indy 500', 'WRC', 'World Rally', 'Superbike', 'WSBK'], ['US', 'UK', 'CA', 'EU'], ['sports']),
    QuickChannel('Soccer / Football', ['Champions League', 'UEFA Champions League', 'Premier League', 'EPL', 'La Liga', 'Serie A', 'Bundesliga', 'Ligue 1', 'MLS', 'World Cup', 'Eredivisie', 'Primeira Liga', 'Süper Lig', 'Super Lig', 'African Football', 'Copa Libertadores', 'SuperSport', 'TNT Sports Football'], ['US', 'UK', 'CA', 'EU'], ['sports']),
    QuickChannel('Viaplay Sports', ['Viaplay', 'Viaplay Sports', 'Viaplay Sports 1', 'Viaplay Sports 2'], ['EU', 'UK', 'CA'], ['sports']),
    QuickChannel('Eleven Sports', ['Eleven Sports', 'Eleven Sports 1', 'Eleven Sports 2', 'Eleven'], ['EU', 'UK'], ['sports']),
    QuickChannel('Setanta Sports', ['Setanta', 'Setanta Sports', 'Setanta Sports 1', 'Setanta Sports 2'], ['EU', 'CA', 'US'], ['sports']),
    QuickChannel('Sport Klub', ['Sport Klub', 'Sport Klub 1', 'Sport Klub 2', 'Sport Klub HD'], ['EU'], ['sports']),
    QuickChannel('Sky Sport Italia', ['Sky Sport', 'Sky Sport Italia', 'Sky Sport 1', 'Sky Sport 24', 'Sky Sport Uno'], ['EU'], ['sports']),
    QuickChannel('Sky Sport DE', ['Sky Sport DE', 'Sky Sport Germany', 'Sky Sport Bundesliga', 'Sky Sport 1 Germany'], ['EU'], ['sports']),
    QuickChannel('RAI Sport', ['Rai Sport', 'RAI Sport', 'Rai Sport 1', 'Rai Sport HD'], ['EU'], ['sports']),
    QuickChannel('RMC Sport', ['RMC Sport', 'RMC Sport 1', 'RMC Sport 2', 'RMC Sport News'], ['EU'], ['sports']),
    QuickChannel('Canal+ Sport', ['Canal+ Sport', 'Canal Plus Sport', 'Canal+ Sport 1', 'Canal+ Sport HD'], ['EU'], ['sports']),
    QuickChannel('Match TV', ['Match TV', 'Match TV Russia', 'Матч ТВ', 'Match TV HD'], ['EU'], ['sports']),
    QuickChannel('Nova Sports', ['Nova Sports', 'Nova Sports 1', 'Nova Sports 2', 'Nova Sports 3', 'NovaSports'], ['EU'], ['sports']),
    QuickChannel('Star Sports India', ['Star Sports', 'Star Sports 1', 'Star Sports 2', 'Star Sports HD', 'Star Sports 1 Hindi'], ['IN'], ['sports']),
    QuickChannel('Sony Sports India', ['Sony Sports', 'Sony Sports 1', 'Sony Sports 2', 'Sony Ten', 'Sony Ten 1', 'Sony Ten 2', 'Sony Ten 3'], ['IN'], ['sports']),
    QuickChannel('ESPN Caribbean', ['ESPN Caribbean', 'ESPN Caribbean HD', 'ESPN Play Caribbean'], ['CA'], ['sports']),
    QuickChannel('Sportsnet World', ['Sportsnet World', 'Sportsnet World HD', 'Sportsnet World 2'], ['CA'], ['sports']),

    // ── 4. PREMIUM MOVIES & ENTERTAINMENT ──────────────────────────
    QuickChannel('HBO & Cinemax', ['HBO', 'HBO US', 'HBO East', 'HBO West', 'HBO 2', 'HBO Signature', 'HBO Family', 'HBO Canada', 'Cinemax', 'MoreMax', 'ActionMax', 'ThrillerMax'], ['US', 'CA'], ['premium']),
    QuickChannel('Premium Movies', ['Showtime', 'Showtime East', 'Starz', 'Starz East', 'Starz Encore', 'Paramount', 'Paramount Network', 'Paramount+', 'Lifetime', 'Lifetime Movies', 'Hallmark', 'Hallmark Channel', 'Hallmark Movies & Mysteries', 'TCM', 'Turner Classic Movies', 'OSN Movies', 'OSN Movies 1', 'OSN Movies 2', 'Netflix', 'Apple TV+'], ['US', 'UK', 'CA', 'EU'], ['premium']),
    QuickChannel('MGM+ & TMC', ['MGM+', 'MGM Plus', 'Epix', 'Epix 2', 'Epix Hits', 'TMC', 'The Movie Channel', 'TMC Extra'], ['US'], ['premium']),
    QuickChannel('Sky Cinema', ['Sky Cinema', 'Sky Cinema Premiere', 'Sky Cinema Greats', 'Sky Cinema Family', 'Sky Cinema Action', 'Sky Cinema Select'], ['UK'], ['premium']),
    QuickChannel('Canadian Premium', ['Crave', 'Crave 1', 'Crave 2', 'Crave 3', 'Crave Movies', 'Super Channel', 'Super Channel Fuse', 'Super Channel Heart & Home'], ['CA'], ['premium']),
    QuickChannel('FXM', ['FXM', 'FX Movie Channel', 'Fox Movies', 'FX Movies'], ['US'], ['premium']),
    QuickChannel('Sony Movies', ['Sony Movies', 'Sony Movies HD', 'Sony Movie Channel', 'Sony Movies Action', 'Sony Movies Classic'], ['US', 'UK', 'CA', 'EU'], ['premium']),
    QuickChannel('Movies!', ['Movies!', 'Movies 1', 'Movies! TV', 'Movies Hd Movies'], ['US'], ['premium']),
    QuickChannel('AXN', ['AXN', 'AXN HD', 'AXN Movies', 'AXN Action'], ['US', 'EU', 'UK', 'CA'], ['premium']),
    QuickChannel('Warner TV', ['Warner TV', 'Warner Channel', 'Warner TV HD', 'Warner Bros TV'], ['US', 'EU', 'CA', 'LA'], ['premium']),
    QuickChannel('Criterion Channel', ['Criterion', 'The Criterion Channel', 'Criterion Channel'], ['US', 'CA', 'EU'], ['premium']),
    QuickChannel('MUBI', ['MUBI', 'MUBI TV', 'MUBI HD'], ['US', 'UK', 'EU', 'CA'], ['premium']),
    QuickChannel('Film4', ['Film4', 'Film 4', 'Film4 HD'], ['UK'], ['premium']),
    QuickChannel('Great! Movies', ['Great! Movies', 'Great! Movies Classic', 'Great Movies UK', 'Good TV Movies'], ['UK'], ['premium']),

    // ── 5. US BROADCAST & CABLE ────────────────────────────────────
    QuickChannel('US Major Broadcast', ['ABC', 'ABC US', 'CBS', 'CBS US', 'NBC', 'NBC US', 'FOX', 'FOX US'], ['US'], ['broadcast']),
    QuickChannel('ION Television', ['ION', 'Ion Television', 'ION TV', 'ION Plus', 'Ion Mystery', 'Ion Life'], ['US'], ['broadcast']),
    QuickChannel('MeTV', ['MeTV', 'Me TV', 'Memorable Entertainment Television', 'MeTV Network'], ['US'], ['broadcast']),
    QuickChannel('Cozi TV', ['Cozi', 'Cozi TV', 'COZI TV'], ['US'], ['broadcast']),
    QuickChannel('Buzzr', ['Buzzr', 'BUZZR', 'Buzzr TV'], ['US'], ['broadcast']),
    QuickChannel('This TV', ['This TV', 'ThisTV', 'This TV Network'], ['US'], ['broadcast']),
    QuickChannel('Decades', ['Decades', 'Decades TV', 'Decades Network'], ['US'], ['broadcast']),
    QuickChannel('Rewind TV', ['Rewind TV', 'Rewind TV Network'], ['US'], ['broadcast']),
    QuickChannel('Antenna TV', ['Antenna TV', 'Antenna TV Network'], ['US'], ['broadcast']),
    QuickChannel('Grit', ['Grit', 'Grit TV', 'GRIT Network'], ['US'], ['broadcast']),
    QuickChannel('Bounce TV', ['Bounce', 'Bounce TV', 'BounceTV'], ['US'], ['broadcast']),
    QuickChannel('UPtv', ['UPtv', 'UP TV', 'UPtv Network'], ['US'], ['broadcast']),
    QuickChannel('Pop TV', ['Pop', 'Pop TV', 'POP TV', 'Pop TV Network'], ['US'], ['entertainment']),
    QuickChannel('TV Land', ['TV Land', 'TVLand', 'TV Land HD'], ['US'], ['entertainment']),
    QuickChannel('Game Show Network', ['Game Show Network', 'GSN', 'Game Show Networks'], ['US'], ['entertainment']),
    QuickChannel('Telemundo', ['Telemundo', 'Telemundo US', 'Telemundo 48', 'Telemundo Internacional'], ['US', 'LA'], ['broadcast']),
    QuickChannel('UniMás', ['UniMas', 'UniMás', 'Unimas', 'Univision UniMas'], ['US', 'LA'], ['broadcast']),
    QuickChannel('US Cable Networks', ['TNT', 'TNT US', 'TNT USA', 'TBS', 'TBS US', 'USA Network', 'USA', 'FX', 'FXX', 'AMC', 'Comedy Central', 'Syfy', 'Bravo', 'Paramount Network', 'TLC', 'HGTV', 'Food Network', 'Discovery Channel', 'History Channel', 'National Geographic'], ['US'], ['entertainment']),
    QuickChannel('TruTV & Reality', ['TruTV', 'trutv', 'Tru TV', 'A&E', 'A&E Network', 'Oxygen', 'Oxygen Network', 'Sundance TV', 'WE tv', 'We TV', 'TLC', 'Bravo', 'E!', 'E! Entertainment', 'Lifetime', 'OWN', 'Oprah Winfrey Network', 'Investigation Discovery'], ['US', 'CA'], ['entertainment']),
    QuickChannel('A&E', ['A&E', 'A&E Network', 'A&E HD'], ['US'], ['entertainment']),
    QuickChannel('OWN', ['OWN', 'OWN US', 'Oprah Winfrey Network'], ['US'], ['entertainment']),
    QuickChannel('Freeform', ['Freeform', 'Freeform HD', 'ABC Family'], ['US'], ['entertainment']),
    QuickChannel('E! Entertainment', ['E!', 'E! Entertainment', 'E! Entertainment Television', 'Style Network'], ['US', 'CA', 'UK'], ['entertainment']),
    QuickChannel('BBC America', ['BBC America', 'BBC America US', 'BBCA'], ['US'], ['entertainment']),
    QuickChannel('Documentary', ['Discovery', 'Discovery Channel', 'Discovery Science', 'History', 'History Channel', 'H2', 'Nat Geo', 'National Geographic', 'National Geographic Wild', 'Animal Planet', 'TLC', 'Food Network', 'HGTV', 'Investigation Discovery', 'ID', 'Cooking Channel', 'Vice', 'Vice TV', 'Smithsonian Channel', 'American Heroes Channel'], ['US', 'UK', 'CA', 'EU'], ['entertainment']),
    QuickChannel('VICE TV', ['Vice', 'VICELAND', 'Viceland', 'VICE TV', 'VICE HD', 'Vice UK', 'Vice Canada'], ['US', 'UK', 'CA'], ['entertainment']),
    QuickChannel('Music Channels', ['MTV', 'MTV Hits', 'MTV Live', 'MTV 00s', 'VH1', 'VH1 Classic', 'BET', 'BET+', 'BET Her', 'MBC Masr', 'MBC Music'], ['US', 'UK', 'CA', 'EU'], ['entertainment']),
    QuickChannel('CMT', ['CMT', 'CMT Music', 'Country Music Television', 'CMT HD'], ['US', 'CA'], ['entertainment']),
    QuickChannel('4Music', ['4Music', '4 Music', '4Music UK'], ['UK'], ['entertainment']),
    QuickChannel('Now 80s', ['Now 80s', 'Now 80s UK', 'NOW 80s'], ['UK'], ['entertainment']),
    QuickChannel('Kerrang!', ['Kerrang', 'Kerrang!', 'Kerrang TV', 'Kerrang Radio TV'], ['UK'], ['entertainment']),
    QuickChannel('Magic Radio TV', ['Magic', 'Magic Radio', 'Magic TV', 'Magic Radio TV'], ['UK'], ['entertainment']),
    QuickChannel('The Box', ['The Box', 'The Box Plus', 'The Box UK', 'The Box Plus Network'], ['UK'], ['entertainment']),
    QuickChannel('Clubland TV', ['Clubland', 'Clubland TV', 'Clubland TV UK'], ['UK'], ['entertainment']),
    QuickChannel('Much', ['Much', 'MuchMusic', 'Much Canada', 'Much Music'], ['CA'], ['entertainment']),
    QuickChannel('Stingray Music', ['Stingray', 'Stingray Music', 'Stingray Hits', 'Stingray Retro', 'Stingray Rock', 'Stingray Top Hits'], ['CA', 'US'], ['entertainment']),
    QuickChannel('Kids & Family', ['Disney Channel', 'Disney XD', 'Disney Junior', 'Cartoon Network', 'CN', 'Adult Swim', 'Nickelodeon', 'Nick', 'Nick Jr', 'NickToons', 'Boomerang', 'PBS Kids', 'Baby TV', 'Baby First', 'Spacetoon'], ['US'], ['kids']),
    QuickChannel('Universal Kids', ['Universal Kids', 'Sprout', 'Universal Kids US'], ['US'], ['kids']),
    QuickChannel('YTV', ['YTV', 'YTV Canada', 'YTV HD'], ['CA'], ['kids']),
    QuickChannel('Treehouse', ['Treehouse', 'Treehouse TV', 'Treehouse Canada'], ['CA'], ['kids']),
    QuickChannel('Family Channel', ['Family Channel', 'Family Channel Canada', 'Family Jr', 'Family CHRGD'], ['CA'], ['kids']),
    QuickChannel('CBeebies', ['CBeebies', 'CBBC', 'Cbeebies UK', 'BBC Cbeebies'], ['UK'], ['kids']),
    QuickChannel('Milkshake!', ['Milkshake', 'Milkshake!', 'Channel 5 Milkshake'], ['UK'], ['kids']),
    QuickChannel('POP UK', ['Pop', 'POP UK', 'Pop Max', 'Pop Kids', 'Tiny Pop'], ['UK'], ['kids']),
    QuickChannel('TVOKids', ['TVO', 'TVOKids', 'TVO Kids', 'TVO Ontario'], ['CA'], ['kids']),

    // ── 6. UK BROADCAST & ENTERTAINMENT ────────────────────────────
    QuickChannel('BBC Networks', ['BBC', 'BBC One', 'BBC1', 'BBC Two', 'BBC2', 'BBC Three', 'BBC Four'], ['UK'], ['broadcast']),
    QuickChannel('UK Commercial Networks', ['ITV', 'ITV1', 'ITV2', 'ITV3', 'ITV4', 'Channel 4', 'C4', 'E4', 'More4', 'Channel 5', '5USA', '5STAR', 'Sky Atlantic', 'Sky Max', 'Sky Showcase'], ['UK'], ['broadcast', 'entertainment']),
    QuickChannel('Sky Arts', ['Sky Arts', 'Sky Arts UK', 'Arts TV'], ['UK'], ['entertainment', 'premium']),
    QuickChannel('Sky Crime', ['Sky Crime', 'Sky Crime UK'], ['UK'], ['entertainment']),
    QuickChannel('Sky History', ['Sky History', 'Sky History UK', 'Sky History 2'], ['UK'], ['entertainment']),
    QuickChannel('Sky Witness', ['Sky Witness', 'Sky Witness UK'], ['UK'], ['entertainment']),
    QuickChannel('W Channel', ['W Channel', 'W UK', 'The W Channel', 'W HD'], ['UK'], ['entertainment']),
    QuickChannel('Dave', ['Dave', 'Dave UK', 'Dave HD', 'Dave Jokes'], ['UK'], ['entertainment']),
    QuickChannel('Gold', ['Gold', 'Gold UK', 'GOLD', 'Gold HD'], ['UK'], ['entertainment']),
    QuickChannel('Drama', ['Drama', 'Drama UK', 'Drama Channel'], ['UK'], ['entertainment']),
    QuickChannel('Yesterday', ['Yesterday', 'Yesterday UK', 'Yesterday Channel'], ['UK'], ['entertainment']),
    QuickChannel('Challenge', ['Challenge', 'Challenge TV', 'Challenge UK'], ['UK'], ['entertainment']),
    QuickChannel('Talking Pictures TV', ['Talking Pictures TV', 'TPTV', 'Talking Pictures'], ['UK'], ['entertainment']),
    QuickChannel('Blaze', ['Blaze', 'Blaze UK', 'Blaze +1'], ['UK'], ['entertainment']),
    QuickChannel('ITVBe', ['ITVBe', 'ITV Be', 'ITVBe UK'], ['UK'], ['entertainment']),
    QuickChannel('Movies4Men', ['Movies4Men', 'Movies 4 Men', 'Movies4Men UK'], ['UK'], ['premium']),
    QuickChannel('London Live', ['London Live', 'London Live UK'], ['UK'], ['entertainment']),

    // ── 7. CANADA & REGIONAL LOCALS ────────────────────────────────
    QuickChannel('Canadian Broadcast', ['CBC', 'CBC Television', 'CTV', 'CTV 2', 'CTV2', 'Global TV', 'Global', 'Showcase', 'W Network'], ['CA'], ['broadcast']),
    QuickChannel('CPAC', ['CPAC', 'CPAC Canada', 'Canadian Parliamentary Channel'], ['CA'], ['news']),
    QuickChannel('TVA', ['TVA', 'TVA Quebec', 'TVA Network', 'TVA HD'], ['CA'], ['broadcast']),
    QuickChannel('Noovo', ['Noovo', 'Noovo Quebec', 'V TV'], ['CA'], ['broadcast']),
    QuickChannel('Vrak', ['Vrak', 'Vrak TV', 'Vrak QC'], ['CA'], ['kids', 'entertainment']),
    QuickChannel('AMI', ['AMI', 'AMI-télé', 'AMI Accessible Media'], ['CA'], ['entertainment']),
    QuickChannel('ABC Spark', ['ABC Spark', 'ABC Spark Canada'], ['CA'], ['entertainment']),
    QuickChannel('CTV Comedy Channel', ['CTV Comedy', 'CTV Comedy Channel', 'The Comedy Channel'], ['CA'], ['entertainment']),
    QuickChannel('CTV Drama Channel', ['CTV Drama', 'CTV Drama Channel', 'BRAVO Canada', 'CTV Sci-Fi Channel'], ['CA'], ['entertainment']),
    QuickChannel('Discovery Science Canada', ['Discovery Science', 'Discovery Science Canada', 'Science Channel Canada', 'The Zone Canada'], ['CA'], ['entertainment']),
    QuickChannel('KTVU Fox 2', ['KTVU', 'KTVU Fox 2', 'FOX 2 KTVU', 'KTVU San Francisco'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KPIX CBS 5', ['KPIX', 'KPIX CBS 5', 'CBS 5 KPIX', 'CBS Bay Area'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KGO ABC 7', ['KGO', 'KGO ABC 7', 'ABC 7 KGO', 'ABC7 Bay Area'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KRON 4', ['KRON', 'KRON 4', 'KRON4', 'KRON News', 'KRON On'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KNTV NBC Bay Area', ['KNTV', 'KNTV NBC 11', 'NBC Bay Area', 'NBC 11', 'KNTV Bay Area'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KQED 9', ['KQED', 'KQED 9', 'KQED PBS', 'PBS KQED', 'KQED Plus'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KBCW CW 44', ['KBCW', 'KBCW CW 44', 'CW 44', 'CW Bay Area'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KICU MyNetwork 36', ['KICU', 'KICU 36', 'MyNetwork 36', 'KICU Bay Area'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KDTV Univision 14', ['KDTV', 'KDTV Univision 14', 'Univision 14', 'Univision Bay Area'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KTSF 26', ['KTSF', 'KTSF 26', 'KTSF Bay Area', 'KTSF 26 San Francisco'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KTVU Fox 2 Plus', ['KTVU Plus', 'KTVU Fox 2 Plus', 'KTVU+'], ['US', 'bay-area'], ['regional']),
    QuickChannel('NBC Bay Area News', ['NBC Bay Area News', 'NBCBA News', 'NBC Bay Area Nonstop'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KPJK 60', ['KPJK', 'KPJK 60', 'KPJK San Francisco'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KRCB 22', ['KRCB', 'KRCB 22', 'KRCB North Bay', 'KRCB PBS'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KCSM 43', ['KCSM', 'KCSM 43', 'KCSM San Mateo'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KEMO 50', ['KEMO', 'KEMO 50', 'KEMO San Francisco'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KMAX CW 31', ['KMAX', 'KMAX 31', 'KMAX CW 31', 'CW 31 KMAX', 'KMAX Sacramento', 'CW Sacramento'], ['US', 'bay-area'], ['regional']),

    // ── 8. INTERNATIONAL & ETHNIC ───────────────────────────────────
    QuickChannel('Zee TV', ['Zee TV', 'Zee TV India', 'Zee TV HD', 'Zee Anmol'], ['IN'], ['entertainment']),
    QuickChannel('Colors TV', ['Colors', 'Colors TV', 'Colors India', 'Colors TV HD'], ['IN'], ['entertainment']),
    QuickChannel('Star Plus', ['Star Plus', 'StarPlus', 'Star Plus HD'], ['IN'], ['entertainment']),
    QuickChannel('Sony Entertainment TV', ['Sony Entertainment', 'Sony TV', 'SET', 'Sony Entertainment Television', 'Sony Sab'], ['IN'], ['entertainment']),
    QuickChannel('Hum TV', ['Hum TV', 'Hum TV Pakistan', 'Hum TV HD'], ['PK'], ['entertainment']),
    QuickChannel('Geo TV', ['Geo TV', 'Geo Entertainment', 'Geo TV Pakistan', 'Geo News'], ['PK'], ['entertainment', 'news']),
    QuickChannel('ARY Digital', ['ARY Digital', 'ARY', 'ARY Digital Pakistan'], ['PK'], ['entertainment']),
    QuickChannel('Aaj Tak', ['Aaj Tak', 'AajTak', 'Aaj Tak HD'], ['IN'], ['news']),
    QuickChannel('Times Now', ['Times Now', 'Times Now India', 'Times Now HD'], ['IN'], ['news']),
    QuickChannel('Republic TV', ['Republic TV', 'Republic Bharat', 'Republic World'], ['IN'], ['news']),
    QuickChannel('NDTV', ['NDTV', 'NDTV India', 'NDTV 24x7'], ['IN'], ['news']),
    QuickChannel('Asianet', ['Asianet', 'Asianet Malayalam', 'Asianet Plus', 'Asianet Movies'], ['IN'], ['entertainment']),
    QuickChannel('Surya TV', ['Surya TV', 'Surya TV Malayalam'], ['IN'], ['entertainment']),
    QuickChannel('Sun TV', ['Sun TV', 'Sun TV Tamil', 'Sun TV India'], ['IN'], ['entertainment']),
    QuickChannel('Vijay TV', ['Vijay TV', 'Star Vijay', 'Vijay TV Tamil'], ['IN'], ['entertainment']),
    QuickChannel('ETV', ['ETV', 'ETV Telugu', 'ETV Plus', 'ETV Cinema'], ['IN'], ['entertainment']),
    QuickChannel('Gemini TV', ['Gemini TV', 'Gemini Telugu', 'Gemini Movies'], ['IN'], ['entertainment']),
    QuickChannel('Dunya News', ['Dunya News', 'Dunya News Pakistan'], ['PK'], ['news']),
    QuickChannel('SAMAA TV', ['SAMAA', 'SAMAA TV', 'Samaa TV Pakistan'], ['PK'], ['news']),
    QuickChannel('Bollywood Movies', ['Bollywood Movies', 'Bollywood', 'B4U Movies', 'Zee Cinema', 'Star Gold'], ['IN'], ['premium']),

    // ── 9. MORE BAY AREA & SACRAMENTO LOCALS ───────────────────────
    QuickChannel('KOFY TV 20', ['KOFY', 'KOFY TV', 'KOFY 20', 'KOFY San Francisco'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KTNC TV', ['KTNC', 'KTNC TV', 'KTNC 42'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KXTV ABC 10', ['KXTV', 'KXTV ABC', 'ABC 10 KXTV', 'News 10 ABC'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KCRA NBC 3', ['KCRA', 'KCRA 3', 'KCRA NBC', 'NBC 3 KCRA'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KOVR CBS 13', ['KOVR', 'KOVR 13', 'KOVR CBS', 'CBS 13 KOVR'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KTXL FOX 40', ['KTXL', 'KTXL FOX', 'FOX 40 KTXL', 'KTXL Sacramento'], ['US', 'bay-area'], ['regional', 'news']),
    QuickChannel('KVIE PBS 6', ['KVIE', 'KVIE PBS', 'PBS KVIE', 'KVIE 6'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KFVT UniMás', ['KFVT', 'KFVT UniMas', 'UniMas Sacramento'], ['US', 'bay-area'], ['regional']),
    QuickChannel('KFSF UniMás 66', ['KFSF', 'KFSF UniMas', 'UniMas 66', 'UniMas Bay Area'], ['US', 'bay-area'], ['regional']),
  ];
}
