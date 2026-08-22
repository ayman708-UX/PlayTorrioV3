class PlaybackHistoryItem {
  final String id;
  final String title;
  final String? poster;
  final String? backdrop;
  final String type; // 'movie' or 'series' or 'anime'
  final String? episodeTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final Duration position;
  final Duration duration;
  final DateTime lastWatched;

  const PlaybackHistoryItem({
    required this.id,
    required this.title,
    this.poster,
    this.backdrop,
    this.type = 'movie',
    this.episodeTitle,
    this.seasonNumber,
    this.episodeNumber,
    required this.position,
    required this.duration,
    required this.lastWatched,
  });

  double get progressPercentage => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  bool get isCompleted => progressPercentage >= 0.90;

  PlaybackHistoryItem copyWith({
    String? id,
    String? title,
    String? poster,
    String? backdrop,
    String? type,
    String? episodeTitle,
    int? seasonNumber,
    int? episodeNumber,
    Duration? position,
    Duration? duration,
    DateTime? lastWatched,
  }) {
    return PlaybackHistoryItem(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      backdrop: backdrop ?? this.backdrop,
      type: type ?? this.type,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      lastWatched: lastWatched ?? this.lastWatched,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster': poster,
        'backdrop': backdrop,
        'type': type,
        'episodeTitle': episodeTitle,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'lastWatched': lastWatched.toIso8601String(),
      };

  factory PlaybackHistoryItem.fromJson(Map<String, dynamic> json) {
    return PlaybackHistoryItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      poster: json['poster'] as String?,
      backdrop: json['backdrop'] as String?,
      type: json['type'] as String? ?? 'movie',
      episodeTitle: json['episodeTitle'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      position: Duration(milliseconds: json['positionMs'] as int? ?? 0),
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      lastWatched: json['lastWatched'] != null
          ? DateTime.tryParse(json['lastWatched'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
