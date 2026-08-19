// Port of `ChannelScorer.kt` from `features/sports`.
import '../../models/iptv/espn_models.dart';
import '../../models/iptv/iptv_models.dart';
import '../../models/iptv/sports_models.dart';
import 'channel_text.dart';
import 'game_to_channel_matcher.dart';

/// A scored match between one [IptvChannel] and a [MatchTarget].
class ChannelScore {
  final IptvChannel channel;
  final MatchType matchType;
  final int score;
  final List<String> reasons;

  const ChannelScore({
    required this.channel,
    required this.matchType,
    required this.score,
    required this.reasons,
  });
}

/// The two teams and league a channel is being tested against.
class MatchTarget {
  final String homeTeam;
  final String awayTeam;
  final String league;
  final String sport;

  const MatchTarget({
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    this.sport = '',
  });

  factory MatchTarget.fromEvent(EspnProcessedEvent event) => MatchTarget(
        homeTeam: event.homeTeam,
        awayTeam: event.awayTeam,
        league: event.league,
        sport: event.sport,
      );
}

class ChannelScorer {
  static const int bothTeams = 100;
  static const int oneTeam = 40;
  static const int epgBothTeams = 60;
  static const int epgOneTeam = 25;
  static const int leagueMatchScore = 15;
  static const int genericSports = 8;
  static const int ambiguousPenalty = -20;

  /// Feeds a cached EPG lookup keyed by normalized channel name -> normalized current title.
  static String Function(String) buildEpgLookup(
    Map<String, String> currentTitleByChannel,
  ) {
    return (rawChannelName) {
      final key = ChannelText.channelNameKey(rawChannelName);
      final direct = currentTitleByChannel[key];
      if (direct != null) return direct;
      final entry = currentTitleByChannel.entries
          .firstWhere(
            (e) => key.length >= 3 && key.contains(e.key),
            orElse: () => const MapEntry('', ''),
          );
      return entry.value;
    };
  }

  static bool _teamPresent(String channelText, List<String> teamKeys) {
    return teamKeys.any((k) => k.isNotEmpty && channelText.contains(k));
  }

  static bool _leagueMatch(
    MatchTarget target,
    String channelName,
    String category,
  ) {
    final league = target.league.trim();
    if (league.isEmpty) return false;
    return GameToChannelMatcher.matchesByLeagueKeywords(
      league,
      channelName,
      category,
    );
  }

  static bool _genericSportsMatch(String channelName, String category) {
    return GameToChannelMatcher.matchesGeneralSportsKeywords(
      channelName,
      category,
    );
  }

  static ChannelScore? scoreChannel(
    MatchTarget target,
    IptvChannel channel, {
    String? currentEpgTitle,
  }) {
    if (GameToChannelMatcher.isNonSportsChannel(
      channel.name,
      channel.group ?? '',
    )) {
      return null;
    }

    final channelName = ChannelText.channelNameKey(channel.name);
    final category = ChannelText.channelNameKey(channel.group ?? '');
    final epgTitle = ChannelText.normalize(currentEpgTitle ?? '');
    final combined = '$channelName $category'.trim();

    if (combined.isEmpty) return null;

    final homeKeys = TeamNameKeys.expand(target.homeTeam, target.league);
    final awayKeys = TeamNameKeys.expand(target.awayTeam, target.league);

    final homeInName = _teamPresent(combined, homeKeys);
    final awayInName = _teamPresent(combined, awayKeys);
    final homeInEpg = _teamPresent(epgTitle, homeKeys);
    final awayInEpg = _teamPresent(epgTitle, awayKeys);

    final reasons = <String>[];
    var score = 0;

    if (homeInName && awayInName) {
      score += bothTeams;
      reasons.add('both teams');
    } else if (homeInName || awayInName) {
      score += oneTeam;
      reasons.add(homeInName ? 'home ${target.homeTeam}' : 'away ${target.awayTeam}');
    }

    if (homeInEpg && awayInEpg) {
      score += epgBothTeams;
      reasons.add('EPG both teams');
    } else if (homeInEpg || awayInEpg) {
      score += epgOneTeam;
      reasons.add('EPG ${homeInEpg ? target.homeTeam : target.awayTeam}');
    }

    if (_leagueMatch(target, channelName, category)) {
      score += leagueMatchScore;
      reasons.add('league ${target.league}');
    } else if (_genericSportsMatch(channelName, category)) {
      score += genericSports;
      reasons.add('sports');
    }

    for (final team in [target.homeTeam, target.awayTeam]) {
      final normalized = ChannelText.normalize(team);
      final first = normalized.split(' ').firstOrNull;
      if (first == null || first.length < 4) continue;
      if (!TeamNameKeys.isAmbiguousFirstWord(first)) continue;
      final second = normalized.split(' ').length > 1
          ? normalized.split(' ')[1]
          : '';
      final hasFull = combined.contains('$first $second'.trim());
      if (combined.contains(first) && !hasFull) {
        score += ambiguousPenalty;
        reasons.add("ambiguous '$first'");
      }
    }

    if (score <= 0) return null;

    final matchType = (homeInName || awayInName)
        ? MatchType.team
        : (_leagueMatch(target, channelName, category)
            ? MatchType.league
            : MatchType.generalSports);

    return ChannelScore(
      channel: channel,
      matchType: matchType,
      score: score,
      reasons: reasons.toSet().toList(),
    );
  }

  static List<ChannelScore> scoreChannels(
    MatchTarget target,
    List<IptvChannel> channels, {
    String Function(String channelName)? currentEpgTitleFor,
  }) {
    final titles = currentEpgTitleFor ?? ((_) => '');
    final scored = <ChannelScore>[];
    for (final ch in channels) {
      final s = scoreChannel(target, ch, currentEpgTitle: titles(ch.name));
      if (s != null) scored.add(s);
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.channel.name.compareTo(b.channel.name);
    });
    return _distinctByUrl(scored);
  }

  /// Same stream URL can appear under multiple sources (M3U + Xtream + Stalker
  /// all point at the same origin). Keep the higher-scoring copy (input is
  /// already score-sorted, so keep the first).
  static List<ChannelScore> _distinctByUrl(List<ChannelScore> input) {
    final seen = <String>{};
    final result = <ChannelScore>[];
    for (final score in input) {
      final url = score.channel.url.trim().toLowerCase();
      if (url.isEmpty || seen.add(url)) {
        result.add(score);
      }
    }
    return result;
  }

  static const int _autoplayScoreFloor = 60;
  static const int _autoplayGap = 20;

  /// Returns the channel that may safely autoplay, or null when the picker
  /// should be shown instead.
  static ChannelScore? autoplayCandidate(List<ChannelScore> scored) {
    final top = scored.firstOrNull;
    if (top == null || top.score < _autoplayScoreFloor) return null;
    final runnerUp = scored.length > 1 ? scored[1] : null;
    if (runnerUp != null && top.score - runnerUp.score < _autoplayGap) {
      return null;
    }
    return top;
  }
}
