// Port of `EspnClient.kt` — ESPN scoreboard API → processed events + sport
// channel matching.
import 'dart:convert';

import '../../models/iptv/espn_models.dart';
import '../../models/iptv/iptv_models.dart';
import '../../models/iptv/sports_models.dart';
import 'channel_scorer.dart';
import 'channel_text.dart';
import 'iptv_http.dart';
import 'iptv_repository.dart';

class EspnClient {
  static const String base = 'https://site.api.espn.com/apis/site/v2/sports';
  static const String _wikiApi =
      'https://en.wikipedia.org/api/rest_v1/page/summary';

  static const List<String> _prioritizedSports = [
    'mma/ufc', 'fighting/ufc',
    'mma/pfl', 'fighting/pfl',
    'mma/boxing', 'fighting/boxing',
    'mma/bkfc', 'fighting/bkfc',
    'mma/bellator', 'fighting/bellator',
    'football/nfl', 'basketball/nba', 'baseball/mlb', 'hockey/nhl',
    'football/college-football', 'basketball/mens-college-basketball',
    'soccer/eng.1', 'soccer/usa.1', 'soccer/esp.1', 'soccer/ita.1',
    'soccer/ger.1', 'soccer/fra.1',
    'basketball/wnba',
    'racing/f1', 'golf/pga', 'tennis/atp', 'tennis/wta',
    'rugby/english-premiership',
  ];

  static const int _perSportTimeoutMs = 5000;
  static const int _earlyBailEventCount = 40;

  static final Map<String, String?> _wikiThumbnailCache = {};
  static final Set<String> _fetchedWikiPages = {};

  static Future<List<EspnProcessedEvent>> fetchLeague(
    String sport,
    String league, {
    String? date,
  }) async {
    final dateParam =
        (date != null && date.trim().isNotEmpty) ? '?dates=${date.replaceAll('-', '')}' : '';
    final url = '$base/$sport/$league/scoreboard$dateParam';
    try {
      final response = await IptvHttp.getText(url, timeout: const Duration(seconds: 12));
      final parsed = _decodeJson(response);
      final events = <EspnProcessedEvent>[];
      for (final e in parsed.events) {
        events.addAll(processEvent(e, '$sport/$league'));
      }
      return await enrichEventImages(events);
    } catch (_) {
      return const [];
    }
  }

  static Future<List<EspnProcessedEvent>> fetchAll({String? date}) async {
    final raw = date ?? '';
    final cleaned = raw.replaceAll('-', '');
    final dateParam = cleaned.isNotEmpty
        ? (cleaned.length == 8
            ? '?dates=$cleaned'
            : '?dates=${cleaned.substring(0, 8)}-${cleaned.substring(8)}')
        : '';
    final isRange = cleaned.isNotEmpty && cleaned.length > 8;
    final skipFilter = raw.trim().isNotEmpty && isRange;

    final results = <EspnProcessedEvent>[];

    for (final sport in _prioritizedSports) {
      if (results.length >= _earlyBailEventCount && raw.trim().isEmpty) break;
      final events = await _fetchSportWithTimeout(sport, dateParam);
      if (events.isNotEmpty) {
        results.addAll(events.where((e) =>
            isRange ||
            e.isLive ||
            e.status != 'STATUS_FINAL' ||
            _detailWithinHours(e.detail, 3) ||
            skipFilter));
      }
      if (results.length >= _earlyBailEventCount && raw.trim().isEmpty) break;
    }
    return enrichEventImages(results);
  }

  static Future<List<EspnProcessedEvent>> _fetchSportWithTimeout(
    String sport,
    String dateParam,
  ) async {
    try {
      final url = '$base/$sport/scoreboard$dateParam';
      final response = await IptvHttp.getText(
        url,
        timeout: const Duration(milliseconds: _perSportTimeoutMs),
      );
      final parsed = _decodeJson(response);
      final events = <EspnProcessedEvent>[];
      for (final e in parsed.events) {
        events.addAll(processEvent(e, sport));
      }
      return events;
    } catch (_) {
      return const [];
    }
  }

  static bool _detailWithinHours(String detail, int hours) {
    if (detail.trim().isEmpty) return false;
    final lower = detail.toLowerCase();
    if (lower.contains('final') || lower.contains('end')) return false;
    return true;
  }

  static EspnResponse _decodeJson(String raw) {
    try {
      final root = jsonDecode(raw);
      if (root is Map<String, dynamic>) return EspnResponse.fromJson(root);
      return const EspnResponse();
    } catch (_) {
      return const EspnResponse();
    }
  }

  static String _teamName(EspnCompetitor? c) {
    final t = c?.team;
    if (t == null) return '';
    return t.displayName.isNotEmpty ? t.displayName : t.name;
  }

  static String _bestLogoUrl(List<EspnLogo>? logos, String? fallback) {
    EspnLogo? best;
    for (final l in logos ?? const <EspnLogo>[]) {
      if (best == null ||
          (l.width * l.height > best.width * best.height)) {
        best = l;
      }
    }
    if (best != null && best.href.isNotEmpty) return best.href;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return '';
  }

  static String _rawDateOrNull(String eventDate, String compDate) {
    final d = eventDate.isNotEmpty ? eventDate : compDate;
    return d.isNotEmpty ? d : '';
  }

  static List<EspnProcessedEvent> processEvent(
    EspnEvent event,
    String sportPath,
  ) {
    final parts = sportPath.split('/');
    final rawSport = parts.isNotEmpty ? parts.first : 'Sport';
    final sport = rawSport == 'mma'
        ? 'Fighting'
        : rawSport.isEmpty
            ? 'Sport'
            : rawSport[0].toUpperCase() + rawSport.substring(1);
    final leagueRaw = parts.length > 1 ? parts[1] : '';
    final league = leagueRaw
        .replaceAll('-', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');

    // ── Fighting sports: consolidate all competitions into one event card ──
    if (sport == 'Fighting') {
      final firstComp = event.competitions.firstOrNull;
      if (firstComp == null) return const [];
      final competitors = firstComp.competitors;

      EspnCompetitor? mainHome;
      for (final c in competitors) {
        if (c.homeAway == 'home') {
          mainHome = c;
          break;
        }
      }
      mainHome ??= competitors.firstOrNull;

      EspnCompetitor? mainAway;
      for (final c in competitors) {
        if (c.homeAway == 'away') {
          mainAway = c;
          break;
        }
      }
      mainAway ??= competitors.length > 1 ? competitors[1] : null;

      final channel = firstComp.broadcasts
              ?.expand((b) => b.names ?? const [])
              .firstOrNull ??
          '';

      final isPpv = channel.toUpperCase().contains('PPV') ||
          (firstComp.notes ?? const []).any(
              (n) => n.type == 'ppv' || n.headline.toUpperCase().contains('PPV'));

      final anyLive = event.competitions
          .any((c) => c.status?.type?.name == 'STATUS_IN_PROGRESS');
      final statusName =
          anyLive ? 'STATUS_IN_PROGRESS' : (firstComp.status?.type?.name ?? '');
      final detail = firstComp.status?.type?.detail ?? '';

      final rawDate = _rawDateOrNull(event.date, firstComp.date).let((d) =>
          d.isNotEmpty ? d : null);
      final dateStr = rawDate != null && rawDate.length >= 10
          ? rawDate.substring(0, 10)
          : '';
      final timeStr = rawDate != null ? extractTime12h(rawDate) : null;

      final eventLogo = _bestLogoUrl(firstComp.logos, event.thumbnail);

      final wikiPage = eventLogo.isEmpty
          ? _guessWikipediaPage(
              event.name.isNotEmpty ? event.name : event.shortName)
          : null;

      final fightCount = event.competitions.length;
      final titleSuffix = fightCount > 1 ? ' (${fightCount} fights)' : '';
      final title =
          (event.shortName.isNotEmpty ? event.shortName : event.name) +
              titleSuffix;

      final mainEventName = (mainHome != null && mainAway != null)
          ? '${_teamName(mainAway)} vs ${_teamName(mainHome)}'
          : event.name;

      return [
        EspnProcessedEvent(
          id: event.id,
          title: title.isNotEmpty ? title : mainEventName,
          homeTeam: _teamName(mainHome),
          awayTeam: _teamName(mainAway),
          homeScore: mainHome?.score,
          awayScore: mainAway?.score,
          homeLogo: eventLogo.isNotEmpty ? eventLogo : null,
          awayLogo: null,
          eventImage: eventLogo.isNotEmpty ? eventLogo : null,
          rawDate: rawDate,
          timeStr: timeStr,
          channel: channel,
          status: statusName,
          detail: detail,
          date: dateStr,
          sport: sport,
          league: league,
          isLive: anyLive,
          isPpv: isPpv,
          wikipediaPage: wikiPage,
          subEventCount: fightCount > 1 ? fightCount : null,
        ),
      ];
    }

    // ── Non-fighting sports: one card per competition ──
    final result = <EspnProcessedEvent>[];
    for (final comp in event.competitions) {
      final competitors = comp.competitors;
      EspnCompetitor? home;
      for (final c in competitors) {
        if (c.homeAway == 'home') {
          home = c;
          break;
        }
      }
      home ??= competitors.firstOrNull;

      EspnCompetitor? away;
      for (final c in competitors) {
        if (c.homeAway == 'away') {
          away = c;
          break;
        }
      }
      away ??= competitors.length > 1 ? competitors[1] : null;

      final channel = comp.broadcasts
              ?.expand((b) => b.names ?? const [])
              .firstOrNull ??
          '';

      final isPpv = channel.toUpperCase().contains('PPV') ||
          (comp.notes ?? const []).any(
              (n) => n.type == 'ppv' || n.headline.toUpperCase().contains('PPV'));

      final statusName = comp.status?.type?.name ?? '';
      final isLive = statusName == 'STATUS_IN_PROGRESS';
      final detail = comp.status?.type?.detail ?? '';

      final rawDate = _rawDateOrNull(event.date, comp.date).let((d) =>
          d.isNotEmpty ? d : null);
      final dateStr = rawDate != null && rawDate.length >= 10
          ? rawDate.substring(0, 10)
          : '';
      final timeStr = rawDate != null ? extractTime12h(rawDate) : null;

      final eventImage = _bestLogoUrl(comp.logos, event.thumbnail);

      final wikiPage = eventImage.isEmpty && sport == 'Fighting'
          ? _guessWikipediaPage(
              event.name.isNotEmpty ? event.name : event.shortName)
          : null;

      result.add(EspnProcessedEvent(
        id: '${event.id}_${comp.id}',
        title: event.shortName.isNotEmpty ? event.shortName : event.name,
        homeTeam: _teamName(home),
        awayTeam: _teamName(away),
        homeScore: home?.score,
        awayScore: away?.score,
        homeLogo: home?.team?.logo,
        awayLogo: away?.team?.logo,
        eventImage: eventImage.isNotEmpty ? eventImage : null,
        rawDate: rawDate,
        timeStr: timeStr,
        channel: channel,
        status: statusName,
        detail: detail,
        date: dateStr,
        sport: sport,
        league: league,
        isLive: isLive,
        isPpv: isPpv,
        wikipediaPage: wikiPage,
      ));
    }
    return result;
  }

  static Future<List<EspnProcessedEvent>> enrichEventImages(
    List<EspnProcessedEvent> events,
  ) async {
    final needWiki = events
        .where((e) => e.eventImage == null && e.wikipediaPage != null)
        .toList();
    if (needWiki.isEmpty) return events;

    for (final e in needWiki) {
      final page = e.wikipediaPage!;
      if (_wikiThumbnailCache.containsKey(page) || _fetchedWikiPages.contains(page)) {
        continue;
      }
      _fetchedWikiPages.add(page);
      String? url;
      try {
        final resp = await IptvHttp.getText(
          '$_wikiApi/${_urlEncode(page)}',
          timeout: const Duration(seconds: 3),
        );
        final obj = jsonDecode(resp);
        if (obj is Map<String, dynamic>) {
          final thumb = obj['thumbnail'];
          if (thumb is Map) {
            url = thumb['source']?.toString();
          }
        }
      } catch (_) {}
      _wikiThumbnailCache[page] = url;
    }

    return events.map((e) {
      final wikiUrl = e.wikipediaPage == null
          ? null
          : _wikiThumbnailCache[e.wikipediaPage];
      if (wikiUrl != null && e.eventImage == null) {
        return e.copyWith(eventImage: wikiUrl);
      }
      return e;
    }).toList();
  }

  static String? _guessWikipediaPage(String title) {
    if (title.trim().isEmpty) return null;
    final ufcMatch = RegExp(r'UFC\s+\d+').firstMatch(title);
    if (ufcMatch != null) return ufcMatch.group(0)!.replaceAll(' ', '_');
    final pflMatch = RegExp(r'PFL\s+\d+').firstMatch(title);
    if (pflMatch != null) return pflMatch.group(0)!.replaceAll(' ', '_');
    final pflYearMatch = RegExp(r'PFL\s+\d{4}').firstMatch(title);
    if (pflYearMatch != null) return pflYearMatch.group(0)!.replaceAll(' ', '_');
    final bellatorMatch =
        RegExp(r'Bellator\s+\d+', caseSensitive: false).firstMatch(title);
    if (bellatorMatch != null) {
      return bellatorMatch.group(0)!.replaceAll(' ', '_');
    }
    return null;
  }

  static String _urlEncode(String s) {
    const unreserved = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final sb = StringBuffer();
    for (final rune in s.runes) {
      final c = String.fromCharCode(rune);
      if (unreserved.contains(c)) {
        sb.write(c);
      } else if (c == ' ') {
        sb.write('%20');
      } else if (c == '_') {
        sb.write('_');
      } else {
        final bytes = utf8.encode(c);
        for (final b in bytes) {
          sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return sb.toString();
  }

  static List<SportEvent> toSportEvents(List<EspnProcessedEvent> processed) {
    return processed.map((e) {
      final teams = e.title.split(RegExp(r' vs | @ | at '));
      final homeName = teams.length >= 2 ? teams.last.trim() : e.homeTeam;
      final awayName = teams.length >= 2 ? teams.first.trim() : e.awayTeam;
      return SportEvent(
        idEvent: e.id,
        strEvent: e.title,
        strSport: e.sport,
        strLeague: e.league,
        strHomeTeam: homeName,
        strAwayTeam: awayName,
        strDate: e.date,
        strTime: e.detail.isNotEmpty ? e.detail : (e.timeStr ?? ''),
        strThumb: e.homeLogo ?? e.awayLogo,
        strChannel: e.channel,
        intHomeScore: e.homeScore,
        intAwayScore: e.awayScore,
        strStatus: e.isLive
            ? 'LIVE'
            : e.status.contains('FINAL')
                ? 'FINAL'
                : 'SCHEDULED',
        strFilename: e.isPpv ? 'PPV' : null,
      );
    }).toList();
  }

  static List<IptvChannel> findAllMatchingChannels(
    SportEvent event,
    List<IptvChannel> channels, {
    String Function(String channelName)? currentEpgTitleFor,
  }) {
    return findScoredMatchingChannels(event, channels,
            currentEpgTitleFor: currentEpgTitleFor)
        .map((c) => c.channel)
        .toList();
  }

  static List<ChannelScore> findScoredMatchingChannels(
    SportEvent event,
    List<IptvChannel> channels, {
    String Function(String channelName)? currentEpgTitleFor,
  }) {
    if (event.strHomeTeam.trim().isEmpty && event.strAwayTeam.trim().isEmpty) {
      return const [];
    }
    final target = MatchTarget(
      homeTeam: event.strHomeTeam,
      awayTeam: event.strAwayTeam,
      league: event.strLeague,
      sport: event.strSport,
    );
    return ChannelScorer.scoreChannels(target, channels,
        currentEpgTitleFor: currentEpgTitleFor);
  }

  /// Two-pass scored variant: fast name/league/generic score first, then lazily
  /// fetch current-program EPG for the top [cap] candidates and re-score.
  static Future<List<ChannelScore>> findScoredMatchingChannelsWithLazyEpg(
    SportEvent event,
    List<IptvChannel> channels, {
    String Function(String channelName)? currentEpgTitleFor,
    int cap = 8,
  }) async {
    if (event.strHomeTeam.trim().isEmpty && event.strAwayTeam.trim().isEmpty) {
      return const [];
    }
    final target = MatchTarget(
      homeTeam: event.strHomeTeam,
      awayTeam: event.strAwayTeam,
      league: event.strLeague,
      sport: event.strSport,
    );
    final fast = ChannelScorer.scoreChannels(target, channels,
        currentEpgTitleFor: currentEpgTitleFor);
    final candidates =
        fast.where((c) => c.score > 0).map((c) => c.channel).toList();
    final lazy = await IptvRepository.instance
        .buildLazyEpgTitleLookup(candidates, cap: cap);
    final combined = (String name) {
      final key = ChannelText.channelNameKey(name);
      final value = lazy[key];
      if (value != null && value.isNotEmpty) return value;
      return currentEpgTitleFor?.call(name) ?? '';
    };
    return ChannelScorer.scoreChannels(target, channels,
        currentEpgTitleFor: combined);
  }

  static List<MatchedSportEvent> matchSportEventsToChannels(
    List<SportEvent> sportEvents,
    List<IptvChannel> channels, {
    String Function(String channelName)? currentEpgTitleFor,
  }) {
    final matched = <MatchedSportEvent>[];
    for (final event in sportEvents) {
      if (event.strHomeTeam.trim().isEmpty && event.strAwayTeam.trim().isEmpty) {
        continue;
      }
      final target = MatchTarget(
        homeTeam: event.strHomeTeam,
        awayTeam: event.strAwayTeam,
        league: event.strLeague,
        sport: event.strSport,
      );
      final top = ChannelScorer.scoreChannels(target, channels,
              currentEpgTitleFor: currentEpgTitleFor)
          .firstOrNull;
      if (top != null) {
        matched.add(MatchedSportEvent(event: event, channel: top.channel));
      }
    }
    return matched;
  }

  /// Extracts a 12-hour AM/PM time from an ISO 8601 UTC timestamp (ESPN style).
  static String? extractTime12h(String iso) {
    final tIdx = iso.indexOf('T');
    if (tIdx < 0) return null;
    var timePart = iso.substring(tIdx + 1);
    final zIdx = timePart.indexOf('Z');
    if (zIdx >= 0) timePart = timePart.substring(0, zIdx);
    final plusIdx = timePart.indexOf('+');
    if (plusIdx >= 0) timePart = timePart.substring(0, plusIdx);
    timePart = timePart.split('-').first;
    final kept = StringBuffer();
    for (final rune in timePart.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      if ((code >= 0x30 && code <= 0x39) || ch == ':') kept.write(ch);
    }
    final clean = kept.toString();
    if (clean.isEmpty) return null;
    final parts = clean.split(':');
    final hour = int.tryParse(parts[0]);
    if (hour == null) return null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    if (hour == 0 && minute == 0) return null;
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final localTotalMinutes = (hour * 60 + minute + offsetMinutes) % (24 * 60);
    final localHour = (localTotalMinutes ~/ 60 + 24) % 24;
    final localMinute = localTotalMinutes % 60;
    final amPm = localHour < 12 ? 'AM' : 'PM';
    final hour12 = localHour == 0
        ? 12
        : (localHour > 12 ? localHour - 12 : localHour);
    final minStr = localMinute.toString().padLeft(2, '0');
    return '$hour12:$minStr $amPm';
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
