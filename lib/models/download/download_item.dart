enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
}

class DownloadItem {
  final String id;
  final String title;
  final String? poster;
  final String? episodeTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final String type; // 'movie' or 'series' or 'anime'
  final String downloadUrl;
  final String? localFilePath;
  final double progress; // 0.0 to 1.0
  final DownloadStatus status;
  final int totalBytes;
  final int receivedBytes;
  final DateTime createdAt;

  const DownloadItem({
    required this.id,
    required this.title,
    this.poster,
    this.episodeTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.type = 'movie',
    required this.downloadUrl,
    this.localFilePath,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    required this.createdAt,
  });

  DownloadItem copyWith({
    String? id,
    String? title,
    String? poster,
    String? episodeTitle,
    int? seasonNumber,
    int? episodeNumber,
    String? type,
    String? downloadUrl,
    String? localFilePath,
    double? progress,
    DownloadStatus? status,
    int? totalBytes,
    int? receivedBytes,
    DateTime? createdAt,
  }) {
    return DownloadItem(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      type: type ?? this.type,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster': poster,
        'episodeTitle': episodeTitle,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'type': type,
        'downloadUrl': downloadUrl,
        'localFilePath': localFilePath,
        'progress': progress,
        'status': status.name,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      poster: json['poster'] as String?,
      episodeTitle: json['episodeTitle'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      type: json['type'] as String? ?? 'movie',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      localFilePath: json['localFilePath'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.queued,
      ),
      totalBytes: json['totalBytes'] as int? ?? 0,
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
