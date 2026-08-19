import 'dart:convert';

import '../iptv/iptv_models.dart';

/// A single stream in the MultiNutz grid. Mirrors `WindowStream` from
/// `MultiWindowStore.kt`.
class WindowStream {
  final String id;
  final String title;
  final String? url;
  final String? poster;
  final IptvChannel? channel;
  final int slotIndex;

  const WindowStream({
    required this.id,
    required this.title,
    this.url,
    this.poster,
    this.channel,
    required this.slotIndex,
  });

  WindowStream copyWith({int? slotIndex, String? title, String? url}) =>
      WindowStream(
        id: id,
        title: title ?? this.title,
        url: url ?? this.url,
        poster: poster,
        channel: channel,
        slotIndex: slotIndex ?? this.slotIndex,
      );
}

/// Resize modes for a multi-window cell (matches `MultiWindowPlayerEngine.kt`).
enum ResizeMode {
  fill,
  fit,
  fixedWidth,
  fixedHeight,
  zoom,
}

/// A saved layout + channel set (bookmark). Mirrors `MultiWindowBookmarks.kt`.
class MultiWindowBookmark {
  final String id;
  final String name;
  final String? layoutName;
  final Map<int, IptvChannel> slotChannels;

  const MultiWindowBookmark({
    required this.id,
    required this.name,
    this.layoutName,
    required this.slotChannels,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'layoutName': layoutName,
        'slots': slotChannels.map(
          (k, v) => MapEntry(k.toString(), v.toJson()),
        ),
      };

  factory MultiWindowBookmark.fromJson(Map<String, dynamic> json) =>
      MultiWindowBookmark(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        layoutName: json['layoutName']?.toString(),
        slotChannels: (json['slots'] as Map<String, dynamic>? ?? {})
            .map(
              (k, v) => MapEntry(
                int.tryParse(k) ?? 0,
                IptvChannel.fromJson(v as Map<String, dynamic>),
              ),
            ),
      );

  static String encodeList(List<MultiWindowBookmark> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<MultiWindowBookmark> decodeList(String raw) {
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => MultiWindowBookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
