import 'cast_member.dart';
import 'link.dart';
import 'video.dart';

class MovieDetail {
  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? logo;
  final String? description;
  final String? year;
  final String? imdbRating;
  final List<String> genres;
  final List<String> cast;
  final List<CastMember> castMembers;
  final List<String> director;
  final List<CrewMember> directorsList;
  final String? runtime;
  final List<Link> links;
  final List<Video> videos;
  final String? tmdbId;

  MovieDetail({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.logo,
    this.description,
    this.year,
    this.imdbRating,
    this.genres = const [],
    this.cast = const [],
    this.castMembers = const [],
    this.director = const [],
    this.directorsList = const [],
    this.runtime,
    this.links = const [],
    this.videos = const [],
    this.tmdbId,
  });

  factory MovieDetail.fromJson(Map<String, dynamic> json) {
    final rawCast = json['cast'];
    final castStrings = _parseStringList(rawCast);
    final parsedCastMembers = _parseCastMembers(rawCast);

    final rawDirector = json['director'] ?? json['directors'];
    final directorStrings = _parseStringList(rawDirector);
    final parsedDirectors = _parseDirectors(rawDirector);

    return MovieDetail(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'movie',
      name: json['name']?.toString() ?? 'Unknown',
      poster: json['poster']?.toString(),
      background: json['background']?.toString(),
      logo: json['logo']?.toString(),
      description: json['description']?.toString(),
      year: json['releaseInfo']?.toString() ?? json['year']?.toString(),
      imdbRating: json['imdbRating']?.toString(),
      genres: _parseStringList(json['genres']),
      cast: castStrings,
      castMembers: parsedCastMembers,
      director: directorStrings,
      directorsList: parsedDirectors,
      runtime: json['runtime']?.toString(),
      links: (json['links'] as List<dynamic>?)
              ?.map((e) => Link.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      videos: (json['videos'] as List<dynamic>?)
              ?.map((e) => Video.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tmdbId: json['moviedb_id']?.toString(),
    );
  }
}

List<CastMember> _parseCastMembers(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    return value.map((e) => CastMember.fromJson(e)).toList();
  }
  if (value is String) {
    return [CastMember(name: value)];
  }
  return [];
}

List<CrewMember> _parseDirectors(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    return value.map((e) => CrewMember.fromJson(e, job: 'Director')).toList();
  }
  if (value is String) {
    return [CrewMember(name: value, job: 'Director')];
  }
  return [];
}

List<String> _parseStringList(dynamic value) {
  if (value == null) return [];
  if (value is String) return [value];
  if (value is List) {
    return value.map((e) {
      if (e is Map) return (e['name'] ?? e['title'] ?? '').toString();
      return e.toString();
    }).where((s) => s.isNotEmpty).toList();
  }
  return [];
}
