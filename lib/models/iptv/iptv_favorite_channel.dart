/// A starred IPTV channel from an M3U playlist or verified Xtream portal.
class IptvFavoriteChannel {
  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String sourceType; // 'm3u' | 'portal'
  final String? playlistId;
  final String? playlistName;
  final String? tvgId;
  final String? portalUrl;
  final String? portalUser;
  final String? portalPass;
  final String? streamId;

  const IptvFavoriteChannel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    required this.sourceType,
    this.playlistId,
    this.playlistName,
    this.tvgId,
    this.portalUrl,
    this.portalUser,
    this.portalPass,
    this.streamId,
  });

  bool get isPortal => sourceType == 'portal';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'streamUrl': streamUrl,
        if (logoUrl != null) 'logoUrl': logoUrl,
        'sourceType': sourceType,
        if (playlistId != null) 'playlistId': playlistId,
        if (playlistName != null) 'playlistName': playlistName,
        if (tvgId != null) 'tvgId': tvgId,
        if (portalUrl != null) 'portalUrl': portalUrl,
        if (portalUser != null) 'portalUser': portalUser,
        if (portalPass != null) 'portalPass': portalPass,
        if (streamId != null) 'streamId': streamId,
      };

  factory IptvFavoriteChannel.fromJson(Map<String, dynamic> j) =>
      IptvFavoriteChannel(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Channel',
        streamUrl: j['streamUrl'] as String? ?? '',
        logoUrl: j['logoUrl'] as String?,
        sourceType: j['sourceType'] as String? ?? 'm3u',
        playlistId: j['playlistId'] as String?,
        playlistName: j['playlistName'] as String?,
        tvgId: j['tvgId'] as String?,
        portalUrl: j['portalUrl'] as String?,
        portalUser: j['portalUser'] as String?,
        portalPass: j['portalPass'] as String?,
        streamId: j['streamId'] as String?,
      );

  IptvFavoriteChannel copyWith({
    String? name,
    String? streamUrl,
    String? logoUrl,
  }) =>
      IptvFavoriteChannel(
        id: id,
        name: name ?? this.name,
        streamUrl: streamUrl ?? this.streamUrl,
        logoUrl: logoUrl ?? this.logoUrl,
        sourceType: sourceType,
        playlistId: playlistId,
        playlistName: playlistName,
        tvgId: tvgId,
        portalUrl: portalUrl,
        portalUser: portalUser,
        portalPass: portalPass,
        streamId: streamId,
      );
}

/// Lightweight EPG row for the home guide.
class IptvGuideEntry {
  final IptvFavoriteChannel channel;
  final String? nowTitle;
  final String? nextTitle;
  final DateTime? nowStart;
  final DateTime? nowStop;

  const IptvGuideEntry({
    required this.channel,
    this.nowTitle,
    this.nextTitle,
    this.nowStart,
    this.nowStop,
  });
}
