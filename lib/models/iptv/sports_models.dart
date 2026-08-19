// Port of `features/sports/SportsModels.kt` + `SportsModels.kt` (iptv package).
import 'iptv_models.dart';

enum MatchType {
  league('League'),
  team('Team'),
  generalSports('Sports');

  final String label;
  const MatchType(this.label);
}

/// One TV event (from thesportsdb or ESPN) that can be matched to IPTV channels.
class SportEvent {
  final String idEvent;
  final String strEvent;
  final String strSport;
  final String strLeague;
  final String strHomeTeam;
  final String strAwayTeam;
  final String strDate;
  final String strTime;
  final String? strThumb;
  final String strChannel;
  final String? intHomeScore;
  final String? intAwayScore;
  final String? strStatus;
  final String? strFilename;
  final String? strVideo;

  const SportEvent({
    required this.idEvent,
    this.strEvent = '',
    this.strSport = '',
    this.strLeague = '',
    this.strHomeTeam = '',
    this.strAwayTeam = '',
    this.strDate = '',
    this.strTime = '',
    this.strThumb,
    this.strChannel = '',
    this.intHomeScore,
    this.intAwayScore,
    this.strStatus,
    this.strFilename,
    this.strVideo,
  });

  factory SportEvent.fromJson(Map<String, dynamic> json) => SportEvent(
        idEvent: json['idEvent']?.toString() ??
            json['id']?.toString() ??
            '',
        strEvent: json['strEvent']?.toString() ?? '',
        strSport: json['strSport']?.toString() ?? '',
        strLeague: json['strLeague']?.toString() ?? '',
        strHomeTeam: json['strHomeTeam']?.toString() ?? '',
        strAwayTeam: json['strAwayTeam']?.toString() ?? '',
        strDate: json['strDate']?.toString() ?? '',
        strTime: json['strTime']?.toString() ?? '',
        strThumb: json['strThumb']?.toString(),
        strChannel: json['strChannel']?.toString() ?? '',
        intHomeScore: json['intHomeScore']?.toString(),
        intAwayScore: json['intAwayScore']?.toString(),
        strStatus: json['strStatus']?.toString(),
        strFilename: json['strFilename']?.toString(),
        strVideo: json['strVideo']?.toString(),
      );
}

class MatchedSportEvent {
  final SportEvent event;
  final IptvChannel channel;

  const MatchedSportEvent({required this.event, required this.channel});
}

class TeamStanding {
  final String teamName;
  final String? logo;
  final String record;
  final String league;
  final String sport;
  final int rank;
  final String netRating;
  final String location;

  const TeamStanding({
    required this.teamName,
    this.logo,
    this.record = '',
    this.league = '',
    this.sport = '',
    this.rank = 0,
    this.netRating = '',
    this.location = '',
  });
}

class MatchedChannel {
  final IptvChannel channel;
  final MatchType matchType;
  final String sourceName;
  final String region;
  final SourceType providerGroup;
  final int score;
  final List<String> reasons;

  const MatchedChannel({
    required this.channel,
    required this.matchType,
    this.sourceName = '',
    this.region = '',
    required this.providerGroup,
    this.score = 0,
    this.reasons = const [],
  });
}
