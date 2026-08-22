// Models for M3U / M3U8 IPTV playlists (uploaded file or URL).
// Decoupled from the Xtream-Codes path — these are simple flat playlists.

class M3uChannel {
  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;
  final String tvgName;

  const M3uChannel({
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '',
    this.tvgId = '',
    this.tvgName = '',
  });

  Map<String, dynamic> toJson() => {
        'n': name,
        'u': url,
        if (logo.isNotEmpty) 'l': logo,
        if (group.isNotEmpty) 'g': group,
        if (tvgId.isNotEmpty) 'ti': tvgId,
        if (tvgName.isNotEmpty) 'tn': tvgName,
      };

  factory M3uChannel.fromJson(Map<String, dynamic> j) => M3uChannel(
        name: j['n'] as String? ?? '',
        url: j['u'] as String? ?? '',
        logo: j['l'] as String? ?? '',
        group: j['g'] as String? ?? '',
        tvgId: j['ti'] as String? ?? '',
        tvgName: j['tn'] as String? ?? '',
      );
}

/// One imported M3U playlist. `sourceUrl` is null when it was uploaded
/// from a local file (so "refresh" is unavailable for that playlist).
class M3uPlaylist {
  final String id;
  final String name;
  final String? sourceUrl;
  final int addedAt;
  final int updatedAt;
  final List<M3uChannel> channels;

  const M3uPlaylist({
    required this.id,
    required this.name,
    required this.sourceUrl,
    required this.addedAt,
    required this.updatedAt,
    required this.channels,
  });

  M3uPlaylist copyWith({
    String? name,
    int? updatedAt,
    List<M3uChannel>? channels,
  }) =>
      M3uPlaylist(
        id: id,
        name: name ?? this.name,
        sourceUrl: sourceUrl,
        addedAt: addedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        channels: channels ?? this.channels,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourceUrl': sourceUrl,
        'addedAt': addedAt,
        'updatedAt': updatedAt,
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  factory M3uPlaylist.fromJson(Map<String, dynamic> j) => M3uPlaylist(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Playlist',
        sourceUrl: j['sourceUrl'] as String?,
        addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        channels: (j['channels'] as List? ?? const [])
            .map((e) => M3uChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
