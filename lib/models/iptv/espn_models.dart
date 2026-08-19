// Port of `EspnModels.kt` — ESPN scoreboard API models + processed event.
//
// Parsed manually (no codegen) with defensive null handling so a malformed
// response never crashes the IPTV tab.

class EspnResponse {
  final List<EspnEvent> events;

  const EspnResponse({this.events = const []});

  factory EspnResponse.fromJson(Map<String, dynamic> json) => EspnResponse(
        events: (json['events'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => EspnEvent.fromJson(e))
            .toList(),
      );
}

class EspnEvent {
  final String id;
  final String name;
  final String shortName;
  final String date;
  final List<EspnCompetition> competitions;
  final String? thumbnail;

  const EspnEvent({
    this.id = '',
    this.name = '',
    this.shortName = '',
    this.date = '',
    this.competitions = const [],
    this.thumbnail,
  });

  factory EspnEvent.fromJson(Map<String, dynamic> json) => EspnEvent(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        shortName: json['shortName']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        competitions: (json['competitions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((c) => EspnCompetition.fromJson(c))
            .toList(),
        thumbnail: json['thumbnail']?.toString(),
      );
}

class EspnCompetition {
  final String id;
  final String date;
  final List<EspnCompetitor> competitors;
  final List<EspnBroadcast>? broadcasts;
  final EspnStatus? status;
  final List<EspnNote>? notes;
  final List<EspnLogo>? logos;

  const EspnCompetition({
    this.id = '',
    this.date = '',
    this.competitors = const [],
    this.broadcasts,
    this.status,
    this.notes,
    this.logos,
  });

  factory EspnCompetition.fromJson(Map<String, dynamic> json) =>
      EspnCompetition(
        id: json['id']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        competitors: (json['competitors'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((c) => EspnCompetitor.fromJson(c))
            .toList(),
        broadcasts: (json['broadcasts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((b) => EspnBroadcast.fromJson(b))
            .toList(),
        status: json['status'] is Map
            ? EspnStatus.fromJson(json['status'] as Map<String, dynamic>)
            : null,
        notes: (json['notes'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((n) => EspnNote.fromJson(n))
            .toList(),
        logos: (json['logos'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((l) => EspnLogo.fromJson(l))
            .toList(),
      );
}

class EspnLogo {
  final String href;
  final int width;
  final int height;

  const EspnLogo({this.href = '', this.width = 0, this.height = 0});

  factory EspnLogo.fromJson(Map<String, dynamic> json) => EspnLogo(
        href: json['href']?.toString() ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

class EspnCompetitor {
  final EspnTeam? team;
  final String? score;
  final String homeAway;

  const EspnCompetitor({this.team, this.score, this.homeAway = ''});

  factory EspnCompetitor.fromJson(Map<String, dynamic> json) =>
      EspnCompetitor(
        team: json['team'] is Map
            ? EspnTeam.fromJson(json['team'] as Map<String, dynamic>)
            : null,
        score: json['score']?.toString(),
        homeAway: json['homeAway']?.toString() ?? '',
      );
}

class EspnTeam {
  final String id;
  final String name;
  final String abbreviation;
  final String displayName;
  final String? logo;
  final String location;

  const EspnTeam({
    this.id = '',
    this.name = '',
    this.abbreviation = '',
    this.displayName = '',
    this.logo,
    this.location = '',
  });

  factory EspnTeam.fromJson(Map<String, dynamic> json) => EspnTeam(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        abbreviation: json['abbreviation']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        logo: json['logo']?.toString(),
        location: json['location']?.toString() ?? '',
      );
}

class EspnBroadcast {
  final List<String>? names;

  const EspnBroadcast({this.names});

  factory EspnBroadcast.fromJson(Map<String, dynamic> json) => EspnBroadcast(
        names: (json['names'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class EspnStatus {
  final EspnStatusType? type;

  const EspnStatus({this.type});

  factory EspnStatus.fromJson(Map<String, dynamic> json) => EspnStatus(
        type: json['type'] is Map
            ? EspnStatusType.fromJson(json['type'] as Map<String, dynamic>)
            : null,
      );
}

class EspnStatusType {
  final String name;
  final String detail;
  final String description;
  final String state;
  final bool completed;

  const EspnStatusType({
    this.name = '',
    this.detail = '',
    this.description = '',
    this.state = '',
    this.completed = false,
  });

  factory EspnStatusType.fromJson(Map<String, dynamic> json) => EspnStatusType(
        name: json['name']?.toString() ?? '',
        detail: json['detail']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        state: json['state']?.toString() ?? '',
        completed: json['completed'] == true,
      );
}

class EspnNote {
  final String headline;
  final String type;

  const EspnNote({this.headline = '', this.type = ''});

  factory EspnNote.fromJson(Map<String, dynamic> json) => EspnNote(
        headline: json['headline']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
      );
}

/// A processed, display-ready sports event (post `processEvent`).
class EspnProcessedEvent {
  final String id;
  final String title;
  final String homeTeam;
  final String awayTeam;
  final String? homeScore;
  final String? awayScore;
  final String? homeLogo;
  final String? awayLogo;
  final String? eventImage;
  final String channel;
  final String status;
  final String detail;
  final String date;
  final String? rawDate;
  final String? timeStr;
  final String sport;
  final String league;
  final bool isLive;
  final bool isPpv;
  final String? wikipediaPage;
  final int? subEventCount;

  const EspnProcessedEvent({
    required this.id,
    required this.title,
    required this.homeTeam,
    required this.awayTeam,
    this.homeScore,
    this.awayScore,
    this.homeLogo,
    this.awayLogo,
    this.eventImage,
    this.channel = '',
    this.status = '',
    this.detail = '',
    this.date = '',
    this.rawDate,
    this.timeStr,
    required this.sport,
    this.league = '',
    this.isLive = false,
    this.isPpv = false,
    this.wikipediaPage,
    this.subEventCount,
  });

  EspnProcessedEvent copyWith({
    String? eventImage,
    String? wikipediaPage,
  }) =>
      EspnProcessedEvent(
        id: id,
        title: title,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeScore: homeScore,
        awayScore: awayScore,
        homeLogo: homeLogo,
        awayLogo: awayLogo,
        eventImage: eventImage ?? this.eventImage,
        channel: channel,
        status: status,
        detail: detail,
        date: date,
        rawDate: rawDate,
        timeStr: timeStr,
        sport: sport,
        league: league,
        isLive: isLive,
        isPpv: isPpv,
        wikipediaPage: wikipediaPage ?? this.wikipediaPage,
        subEventCount: subEventCount,
      );
}
