// Port of `IptvModels.kt` — data models for the IPTVNutz feature.
import 'dart:convert';

enum SourceType { m3u, xtream, stalker }

class M3uPlaylist {
  final String id;
  final String name;
  final String url;
  final List<IptvChannel> channels;

  const M3uPlaylist({
    required this.id,
    required this.name,
    required this.url,
    this.channels = const [],
  });

  M3uPlaylist copyWith({List<IptvChannel>? channels}) => M3uPlaylist(
        id: id,
        name: name,
        url: url,
        channels: channels ?? this.channels,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  factory M3uPlaylist.fromJson(Map<String, dynamic> json) => M3uPlaylist(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        channels: (json['channels'] as List<dynamic>? ?? [])
            .map((e) => IptvChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PortalAccountInfo {
  final String? expDate;
  final int? maxConnections;
  final int? activeConnections;
  final String? status;
  final bool isTrial;

  const PortalAccountInfo({
    this.expDate,
    this.maxConnections,
    this.activeConnections,
    this.status,
    this.isTrial = false,
  });

  Map<String, dynamic> toJson() => {
        'expDate': expDate,
        'maxConnections': maxConnections,
        'activeConnections': activeConnections,
        'status': status,
        'isTrial': isTrial,
      };

  factory PortalAccountInfo.fromJson(Map<String, dynamic> json) =>
      PortalAccountInfo(
        expDate: json['expDate']?.toString(),
        maxConnections: (json['maxConnections'] as num?)?.toInt(),
        activeConnections: (json['activeConnections'] as num?)?.toInt(),
        status: json['status']?.toString(),
        isTrial: json['isTrial'] == true,
      );
}

class XtreamAccount {
  final String id;
  final String name;
  final String server;
  final String username;
  final String password;
  final PortalAccountInfo? info;
  final List<XtreamCategory> categories;
  final List<IptvChannel> channels;

  const XtreamAccount({
    required this.id,
    required this.name,
    required this.server,
    required this.username,
    required this.password,
    this.info,
    this.categories = const [],
    this.channels = const [],
  });

  XtreamAccount copyWith({
    PortalAccountInfo? info,
    List<XtreamCategory>? categories,
    List<IptvChannel>? channels,
  }) =>
      XtreamAccount(
        id: id,
        name: name,
        server: server,
        username: username,
        password: password,
        info: info ?? this.info,
        categories: categories ?? this.categories,
        channels: channels ?? this.channels,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'server': server,
        'username': username,
        'password': password,
        'info': info?.toJson(),
        'categories': categories
            .map((c) => {'id': c.id, 'name': c.name})
            .toList(),
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  factory XtreamAccount.fromJson(Map<String, dynamic> json) => XtreamAccount(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        server: json['server'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        info: json['info'] is Map
            ? PortalAccountInfo.fromJson(json['info'] as Map<String, dynamic>)
            : null,
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((e) => XtreamCategory(
                  id: (e as Map<String, dynamic>)['id']?.toString() ?? '',
                  name: e['name']?.toString() ?? '',
                ))
            .toList(),
        channels: (json['channels'] as List<dynamic>? ?? [])
            .map((e) => IptvChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class StalkerAccount {
  final String id;
  final String name;
  final String server;
  final String macAddress;
  final List<IptvChannel> channels;

  const StalkerAccount({
    required this.id,
    required this.name,
    required this.server,
    required this.macAddress,
    this.channels = const [],
  });

  StalkerAccount copyWith({List<IptvChannel>? channels}) => StalkerAccount(
        id: id,
        name: name,
        server: server,
        macAddress: macAddress,
        channels: channels ?? this.channels,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'server': server,
        'macAddress': macAddress,
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  factory StalkerAccount.fromJson(Map<String, dynamic> json) => StalkerAccount(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        server: json['server'] as String? ?? '',
        macAddress: json['macAddress'] as String? ?? '',
        channels: (json['channels'] as List<dynamic>? ?? [])
            .map((e) => IptvChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class XtreamCategory {
  final String id;
  final String name;

  const XtreamCategory({required this.id, required this.name});
}

/// One playable TV channel, regardless of source type.
class IptvChannel {
  final String id;
  final String name;
  final String? logo;
  final String? group;
  final String url;
  final String? audioUrl;
  final List<String> qualities;
  final String? epgChannelId;
  final SourceType sourceType;
  final String sourceId;

  const IptvChannel({
    required this.id,
    required this.name,
    this.logo,
    this.group,
    required this.url,
    this.audioUrl,
    this.qualities = const [],
    this.epgChannelId,
    required this.sourceType,
    required this.sourceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'logo': logo,
        'group': group,
        'url': url,
        'audioUrl': audioUrl,
        'qualities': qualities,
        'epgChannelId': epgChannelId,
        'sourceType': sourceType.name,
        'sourceId': sourceId,
      };

  factory IptvChannel.fromJson(Map<String, dynamic> json) => IptvChannel(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        logo: json['logo']?.toString(),
        group: json['group']?.toString(),
        url: json['url'] as String? ?? '',
        audioUrl: json['audioUrl']?.toString(),
        qualities: (json['qualities'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        epgChannelId: json['epgChannelId']?.toString(),
        sourceType: SourceType.values
            .firstWhere(
              (e) => e.name == json['sourceType'],
              orElse: () => SourceType.m3u,
            ),
        sourceId: json['sourceId'] as String? ?? '',
      );
}

class EpgSource {
  final String id;
  final String name;
  final String url;

  const EpgSource({required this.id, required this.name, required this.url});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};

  factory EpgSource.fromJson(Map<String, dynamic> json) => EpgSource(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class EpgProgram {
  final String channelId;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final String? icon;

  const EpgProgram({
    required this.channelId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.icon,
  });

  bool get isNow {
    final now = DateTime.now();
    return startTime.isBefore(now) && endTime.isAfter(now);
  }
}

/// UI state for the IPTVNutz tab (mirrors `IptvUiState` from `IptvModels.kt`).
class IptvUiState {
  final List<M3uPlaylist> m3uPlaylists;
  final List<XtreamAccount> xtreamAccounts;
  final List<StalkerAccount> stalkerAccounts;
  final List<EpgSource> epgSources;
  final List<String> favoriteChannelIds;
  final List<String> channelHistory;
  final List<IptvChannel> channels;
  final Set<String> selectedSourceIds;
  final String? selectedCategory;
  final String searchQuery;
  final bool isLoading;
  final String? error;
  final Set<String> refreshingSourceIds;
  final bool epgLoading;
  final String? epgError;
  final int epgMatchCount;
  final bool playlistsExpanded;
  final bool channelsExpanded;
  final bool favoritesExpanded;

  const IptvUiState({
    this.m3uPlaylists = const [],
    this.xtreamAccounts = const [],
    this.stalkerAccounts = const [],
    this.epgSources = const [],
    this.favoriteChannelIds = const [],
    this.channelHistory = const [],
    this.channels = const [],
    this.selectedSourceIds = const {},
    this.selectedCategory,
    this.searchQuery = '',
    this.isLoading = false,
    this.error,
    this.refreshingSourceIds = const {},
    this.epgLoading = false,
    this.epgError,
    this.epgMatchCount = 0,
    this.playlistsExpanded = true,
    this.channelsExpanded = true,
    this.favoritesExpanded = true,
  });

  IptvUiState copyWith({
    List<M3uPlaylist>? m3uPlaylists,
    List<XtreamAccount>? xtreamAccounts,
    List<StalkerAccount>? stalkerAccounts,
    List<EpgSource>? epgSources,
    List<String>? favoriteChannelIds,
    List<String>? channelHistory,
    List<IptvChannel>? channels,
    Set<String>? selectedSourceIds,
    String? selectedCategory,
    String? searchQuery,
    bool? isLoading,
    String? error,
    Set<String>? refreshingSourceIds,
    bool? epgLoading,
    String? epgError,
    int? epgMatchCount,
    bool? playlistsExpanded,
    bool? channelsExpanded,
    bool? favoritesExpanded,
    bool clearError = false,
  }) {
    return IptvUiState(
      m3uPlaylists: m3uPlaylists ?? this.m3uPlaylists,
      xtreamAccounts: xtreamAccounts ?? this.xtreamAccounts,
      stalkerAccounts: stalkerAccounts ?? this.stalkerAccounts,
      epgSources: epgSources ?? this.epgSources,
      favoriteChannelIds: favoriteChannelIds ?? this.favoriteChannelIds,
      channelHistory: channelHistory ?? this.channelHistory,
      channels: channels ?? this.channels,
      selectedSourceIds: selectedSourceIds ?? this.selectedSourceIds,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      refreshingSourceIds:
          refreshingSourceIds ?? this.refreshingSourceIds,
      epgLoading: epgLoading ?? this.epgLoading,
      epgError: epgError ?? this.epgError,
      epgMatchCount: epgMatchCount ?? this.epgMatchCount,
      playlistsExpanded: playlistsExpanded ?? this.playlistsExpanded,
      channelsExpanded: channelsExpanded ?? this.channelsExpanded,
      favoritesExpanded: favoritesExpanded ?? this.favoritesExpanded,
    );
  }
}

/// Persisted IPTV settings (playlists, accounts, EPG sources, favorites, history).
class IptvSettings {
  final List<M3uPlaylist> m3uPlaylists;
  final List<XtreamAccount> xtreamAccounts;
  final List<StalkerAccount> stalkerAccounts;
  final List<EpgSource> epgSources;
  final List<String> favoriteChannelIds;
  final List<String> historyChannelIds;

  const IptvSettings({
    this.m3uPlaylists = const [],
    this.xtreamAccounts = const [],
    this.stalkerAccounts = const [],
    this.epgSources = const [],
    this.favoriteChannelIds = const [],
    this.historyChannelIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'm3u': m3uPlaylists.map((e) => e.toJson()).toList(),
        'xtream': xtreamAccounts.map((e) => e.toJson()).toList(),
        'stalker': stalkerAccounts.map((e) => e.toJson()).toList(),
        'epg': epgSources.map((e) => e.toJson()).toList(),
        'favorites': favoriteChannelIds,
        'history': historyChannelIds,
      };

  factory IptvSettings.fromJson(Map<String, dynamic> json) => IptvSettings(
        m3uPlaylists: (json['m3u'] as List<dynamic>? ?? [])
            .map((e) => M3uPlaylist.fromJson(e as Map<String, dynamic>))
            .toList(),
        xtreamAccounts: (json['xtream'] as List<dynamic>? ?? [])
            .map((e) => XtreamAccount.fromJson(e as Map<String, dynamic>))
            .toList(),
        stalkerAccounts: (json['stalker'] as List<dynamic>? ?? [])
            .map((e) => StalkerAccount.fromJson(e as Map<String, dynamic>))
            .toList(),
        epgSources: (json['epg'] as List<dynamic>? ?? [])
            .map((e) => EpgSource.fromJson(e as Map<String, dynamic>))
            .toList(),
        favoriteChannelIds: (json['favorites'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        historyChannelIds: (json['history'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  static String encode(IptvSettings s) => jsonEncode(s.toJson());

  static IptvSettings decode(String raw) {
    try {
      return IptvSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const IptvSettings();
    }
  }
}
