import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Result of parsing in a background isolate (avoids UI jank on large EPG files).
class _XmltvParsedData {
  final Map<String, List<XmltvProgramme>> byChannel;
  final Map<String, String> normToRawId;
  final Map<String, String> normToDisplayName;

  const _XmltvParsedData({
    required this.byChannel,
    required this.normToRawId,
    required this.normToDisplayName,
  });
}

/// Parses XMLTV (xmltv) files and maps programmes to channel ids for TV Guide.
class XmltvEpgService {
  XmltvEpgService._();
  static final XmltvEpgService instance = XmltvEpgService._();

  /// Normalized keys → programmes (start ascending).
  final Map<String, List<XmltvProgramme>> _byChannel = {};

  /// Normalized channel key → raw `id` attribute (first seen).
  final Map<String, String> _normToRawId = {};

  /// Normalized channel key → best display label from `<channel>` (for picker UI).
  final Map<String, String> _normToDisplayName = {};

  bool get isLoaded => _byChannel.isNotEmpty || _normToRawId.isNotEmpty;

  /// Raw channel ids from the file, sorted by display name for pickers.
  List<String> get loadedChannelIds {
    final norms = {..._byChannel.keys, ..._normToRawId.keys};
    final raw = norms.map((n) => _normToRawId[n] ?? n).toList();
    raw.sort((a, b) {
      final la = displayNameForChannelId(a).toLowerCase();
      final lb = displayNameForChannelId(b).toLowerCase();
      final c = la.compareTo(lb);
      return c != 0 ? c : a.toLowerCase().compareTo(b.toLowerCase());
    });
    return raw;
  }

  /// User-facing label for a raw or normalized id (falls back to [id]).
  String displayNameForChannelId(String id) {
    final n = normalizeKey(id);
    final fromMeta = _normToDisplayName[n];
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
    return id;
  }

  void clear() {
    _byChannel.clear();
    _normToRawId.clear();
    _normToDisplayName.clear();
  }

  static String normalizeKey(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), '');
    t = t.replaceAll(RegExp(r'[^a-z0-9._:-]'), '');
    return t;
  }

  /// XMLTV datetime: `YYYYMMDDHHmmss` with optional ` +0200` offset.
  static DateTime? parseXmltvTime(String? raw) {
    if (raw == null || raw.length < 14) return null;
    final space = raw.indexOf(' ');
    final core = space >= 0 ? raw.substring(0, space) : raw.substring(0, 14);
    if (core.length < 14) return null;
    try {
      final y = int.parse(core.substring(0, 4));
      final mo = int.parse(core.substring(4, 6));
      final d = int.parse(core.substring(6, 8));
      final h = int.parse(core.substring(8, 10));
      final mi = int.parse(core.substring(10, 12));
      final sec = int.parse(core.substring(12, 14));
      if (space > 15 && raw.length > space + 5) {
        final tz = raw.substring(space + 1).trim();
        if (tz.length >= 5 && (tz.startsWith('+') || tz.startsWith('-'))) {
          final sign = tz.startsWith('-') ? -1 : 1;
          final th = int.tryParse(tz.substring(1, 3)) ?? 0;
          final tmi = int.tryParse(tz.substring(3, 5)) ?? 0;
          final offset = Duration(hours: sign * th, minutes: sign * tmi);
          final utc = DateTime.utc(y, mo, d, h, mi, sec).subtract(offset);
          return utc.toLocal();
        }
      }
      return DateTime(y, mo, d, h, mi, sec);
    } catch (_) {
      return null;
    }
  }

  static String _elemText(XmlElement parent, String name) {
    final el = parent.findElements(name).firstOrNull;
    return el?.innerText.trim() ?? '';
  }

  void _applyParsedData(_XmltvParsedData data) {
    _byChannel
      ..clear()
      ..addAll(data.byChannel);
    _normToRawId
      ..clear()
      ..addAll(data.normToRawId);
    _normToDisplayName
      ..clear()
      ..addAll(data.normToDisplayName);
  }

  /// Loads [url] only when not already loaded or [url] changed.
  String? _loadedUrl;

  Future<bool> ensureLoaded(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    if (_loadedUrl == trimmed && isLoaded) return true;
    final ok = await loadFromUrl(trimmed);
    if (ok) _loadedUrl = trimmed;
    return ok;
  }

  List<XmltvProgramme> programmesForChannel(String tvgId) {
    final now = DateTime.now();
    return programmesFor(
      tvgId: tvgId,
      from: now.subtract(const Duration(hours: 1)),
      to: now.add(const Duration(hours: 12)),
      maxItems: 8,
    );
  }

  /// Fetches and parses an XMLTV document from [url]. Clears previous data.
  /// Heavy parsing runs in a background isolate so the UI thread does not freeze.
  Future<bool> loadFromUrl(String url) async {
    clear();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return false;

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return false;
      final bytes = Uint8List.fromList(response.bodyBytes);
      final data = await compute(_parseXmltvBytesInIsolate, bytes);
      if (data == null) {
        clear();
        return false;
      }
      _applyParsedData(data);
      return isLoaded;
    } catch (_) {
      return false;
    }
  }

  static String? _channelDisplayName(XmlElement channelEl) {
    XmlElement? pick;
    for (final el in channelEl.findElements('display-name')) {
      final lang = el.getAttribute('lang')?.toLowerCase() ?? '';
      if (lang.isEmpty || lang.startsWith('en')) {
        pick = el;
        break;
      }
      pick ??= el;
    }
    final t = pick?.innerText.trim() ?? '';
    return t.isNotEmpty ? t : null;
  }

  /// Top-level for [compute] — must not touch [XmltvEpgService.instance].
  static _XmltvParsedData? _parseXmltvBytesInIsolate(Uint8List bytes) {
    try {
      String body;
      if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        body = utf8.decode(GZipDecoder().decodeBytes(bytes));
      } else {
        body = utf8.decode(bytes);
      }
      return _parseXmlStringToData(body);
    } catch (_) {
      return null;
    }
  }

  static _XmltvParsedData? _parseXmlStringToData(String body) {
    try {
      final doc = XmlDocument.parse(body);
      final byChannel = <String, List<XmltvProgramme>>{};
      final normToRawId = <String, String>{};
      final normToDisplayName = <String, String>{};

      void registerRawId(String channelId) {
        final k = normalizeKey(channelId);
        if (k.isEmpty) return;
        normToRawId.putIfAbsent(k, () => channelId.trim());
      }

      void addProgramme(String channelId, XmltvProgramme p) {
        final k = normalizeKey(channelId);
        if (k.isEmpty) return;
        registerRawId(channelId);
        byChannel.putIfAbsent(k, () => []).add(p);
      }

      for (final cel in doc.findAllElements('channel')) {
        final id = cel.getAttribute('id');
        if (id == null || id.isEmpty) continue;
        registerRawId(id);
        final dn = _channelDisplayName(cel);
        if (dn != null) {
          final k = normalizeKey(id);
          normToDisplayName.putIfAbsent(k, () => dn);
        }
      }

      for (final prog in doc.findAllElements('programme')) {
        final ch = prog.getAttribute('channel');
        if (ch == null || ch.isEmpty) continue;
        final start = parseXmltvTime(prog.getAttribute('start'));
        if (start == null) continue;
        final stopRaw = prog.getAttribute('stop');
        final stop = parseXmltvTime(stopRaw) ?? start.add(const Duration(hours: 1));
        final title = _elemText(prog, 'title');
        if (title.isEmpty) continue;
        final sub = _elemText(prog, 'sub-title');
        final desc = _elemText(prog, 'desc');
        addProgramme(
          ch,
          XmltvProgramme(
            start: start,
            end: stop,
            title: title,
            subtitle: sub.isNotEmpty ? sub : (desc.isNotEmpty ? desc : null),
          ),
        );
      }

      for (final list in byChannel.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }

      final empty = byChannel.isEmpty && normToRawId.isEmpty;
      if (empty) return null;
      return _XmltvParsedData(
        byChannel: byChannel,
        normToRawId: normToRawId,
        normToDisplayName: normToDisplayName,
      );
    } catch (_) {
      return null;
    }
  }

  Iterable<String> _candidateKeys(String? tvgId, String? channelName, String? stremioId) sync* {
    if (tvgId != null && tvgId.isNotEmpty) {
      yield normalizeKey(tvgId);
      final noDot = tvgId.replaceAll('.', '');
      if (noDot != tvgId) yield normalizeKey(noDot);
    }
    if (channelName != null && channelName.isNotEmpty) {
      yield normalizeKey(channelName);
      yield normalizeKey(channelName.replaceAll(' ', '.'));
      final noSpace = channelName.replaceAll(RegExp(r'\s+'), '');
      if (noSpace != channelName) yield normalizeKey(noSpace);
      final slug = channelName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '');
      if (slug.isNotEmpty) yield normalizeKey(slug);
    }
    if (stremioId != null && stremioId.contains(':')) {
      final tail = stremioId.split(':').last;
      if (tail.isNotEmpty) {
        yield normalizeKey(tail);
        if (tail.contains('-')) {
          final parts = tail.split('-');
          if (parts.length > 1) yield normalizeKey(parts.last);
        }
      }
    }
  }

  /// Programmes overlapping [from]..[to] for the best-matching channel id.
  /// [epgChannelOverride] is tried first (manual match from Settings).
  /// Overlapping programmes in [from]..[to] for the first matching channel key.
  /// [maxItems] caps the returned list only after the full window is collected (so
  /// "now" is not dropped when many programmes precede it in the same window).
  List<XmltvProgramme> programmesFor({
    String? tvgId,
    String? channelName,
    String? stremioId,
    String? epgChannelOverride,
    required DateTime from,
    required DateTime to,
    int? maxItems,
  }) {
    final seen = <String>{};
    Iterable<String> keys() sync* {
      if (epgChannelOverride != null && epgChannelOverride.trim().isNotEmpty) {
        yield normalizeKey(epgChannelOverride.trim());
      }
      for (final k in _candidateKeys(tvgId, channelName, stremioId)) {
        if (seen.add(k)) yield k;
      }
    }

    for (final key in keys()) {
      final list = _byChannel[key];
      if (list == null || list.isEmpty) continue;
      final out = <XmltvProgramme>[];
      const safetyCap = 800;
      for (final p in list) {
        if (p.end.isBefore(from) || !p.start.isBefore(to)) continue;
        out.add(p);
        if (out.length >= safetyCap) break;
      }
      if (out.isEmpty) continue;
      if (maxItems != null && out.length > maxItems) {
        final now = DateTime.now();
        var anchor = 0;
        for (var i = 0; i < out.length; i++) {
          if (!out[i].end.isBefore(now)) {
            anchor = i;
            break;
          }
        }
        final maxStart = out.length - maxItems;
        final start = (anchor - (maxItems ~/ 2)).clamp(0, maxStart < 0 ? 0 : maxStart);
        final end = (start + maxItems).clamp(0, out.length);
        return out.sublist(start, end);
      }
      return out;
    }
    return [];
  }
}

class XmltvProgramme {
  final DateTime start;
  final DateTime end;
  final String title;
  final String? subtitle;

  const XmltvProgramme({
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
  });
}
