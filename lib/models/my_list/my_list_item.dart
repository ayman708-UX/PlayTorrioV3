enum MyListSource { local, trakt }

class MyListItem {
  final int? traktId;
  final String? imdbId;
  final int? tmdbId;
  final String title;
  final int? year;
  final String type;
  final String? poster;
  final DateTime addedAt;
  final MyListSource source;
  final bool isWatchlist;

  const MyListItem({
    this.traktId,
    this.imdbId,
    this.tmdbId,
    required this.title,
    this.year,
    required this.type,
    this.poster,
    required this.addedAt,
    this.source = MyListSource.local,
    this.isWatchlist = false,
  });

  String get uniqueKey {
    if (traktId != null) return 'trakt:$traktId';
    if (imdbId != null) return 'imdb:$imdbId';
    if (tmdbId != null) return 'tmdb:$tmdbId';
    return 'title:${title.toLowerCase().trim()}:${year ?? 0}';
  }

  factory MyListItem.fromMovie({
    required String id,
    required String name,
    String? poster,
    String? year,
    required String type,
    String? imdbId,
    int? tmdbId,
  }) {
    return MyListItem(
      imdbId: id.startsWith('tt') ? id : imdbId,
      tmdbId: tmdbId ?? (int.tryParse(id) != null && !id.startsWith('tt') ? int.tryParse(id) : null),
      title: name,
      poster: poster,
      year: year != null ? int.tryParse(year.replaceAll(RegExp(r'[^0-9]'), '')) : null,
      type: type == 'series' || type == 'anime' ? 'series' : 'movie',
      addedAt: DateTime.now(),
      source: MyListSource.local,
    );
  }

  factory MyListItem.fromMovieDetail({
    required String id,
    required String name,
    String? poster,
    String? year,
    required String type,
    String? imdbId,
    int? tmdbId,
  }) {
    return MyListItem(
      imdbId: id.startsWith('tt') ? id : imdbId,
      tmdbId: tmdbId ?? (int.tryParse(id) != null && !id.startsWith('tt') ? int.tryParse(id) : null),
      title: name,
      poster: poster,
      year: year != null ? int.tryParse(year.replaceAll(RegExp(r'[^0-9]'), '')) : null,
      type: type == 'series' || type == 'anime' ? 'series' : 'movie',
      addedAt: DateTime.now(),
      source: MyListSource.local,
    );
  }

  factory MyListItem.fromTraktJson(Map<String, dynamic> json) {
    final movie = json['movie'] as Map<String, dynamic>?;
    final show = json['show'] as Map<String, dynamic>?;
    final media = movie ?? show ?? json;
    final ids = media['ids'] as Map<String, dynamic>? ?? {};
    return MyListItem(
      traktId: ids['trakt'] as int?,
      imdbId: ids['imdb']?.toString(),
      tmdbId: ids['tmdb'] as int?,
      title: media['title']?.toString() ?? 'Unknown',
      year: media['year'] as int?,
      type: (media['type']?.toString() == 'show' || show != null) ? 'series' : 'movie',
      addedAt: json['listed_at'] != null
          ? DateTime.tryParse(json['listed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: MyListSource.trakt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'traktId': traktId,
      'imdbId': imdbId,
      'tmdbId': tmdbId,
      'title': title,
      'year': year,
      'type': type,
      'poster': poster,
      'addedAt': addedAt.toIso8601String(),
      'source': source.name,
      'isWatchlist': isWatchlist,
    };
  }

  factory MyListItem.fromJson(Map<String, dynamic> json) {
    return MyListItem(
      traktId: json['traktId'] as int?,
      imdbId: json['imdbId']?.toString(),
      tmdbId: json['tmdbId'] as int?,
      title: json['title']?.toString() ?? 'Unknown',
      year: json['year'] as int?,
      type: json['type']?.toString() ?? 'movie',
      poster: json['poster']?.toString(),
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      source: json['source'] == 'trakt' ? MyListSource.trakt : MyListSource.local,
      isWatchlist: json['isWatchlist'] as bool? ?? false,
    );
  }

  MyListItem copyWith({
    int? traktId,
    String? imdbId,
    int? tmdbId,
    String? title,
    int? year,
    String? type,
    String? poster,
    DateTime? addedAt,
    MyListSource? source,
  }) {
    return MyListItem(
      traktId: traktId ?? this.traktId,
      imdbId: imdbId ?? this.imdbId,
      tmdbId: tmdbId ?? this.tmdbId,
      title: title ?? this.title,
      year: year ?? this.year,
      type: type ?? this.type,
      poster: poster ?? this.poster,
      addedAt: addedAt ?? this.addedAt,
      source: source ?? this.source,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MyListItem && uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}
