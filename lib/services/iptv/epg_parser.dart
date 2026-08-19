import '../../models/iptv/iptv_models.dart';

/// Result of parsing XMLTV EPG data.
class EpgParseResult {
  final Map<String, List<EpgProgram>> programsByChannelId;
  final Map<String, String> channelDisplayNames;

  const EpgParseResult({
    required this.programsByChannelId,
    required this.channelDisplayNames,
  });
}

/// Port of `EpgParser.kt` — parses XMLTV EPG content (full-string variant).
class EpgParser {
  static EpgParseResult parseXmltv(String xmlContent) {
    final channelNames = <String, String>{};

    final channelRegex = RegExp('<channel\\s+id="([^"]+)"[^>]*>');
    final displayNameRegex = RegExp('<display-name>([^<]*)</display-name>');
    var chIdx = 0;
    while (true) {
      final chMatch = channelRegex.firstMatch(xmlContent.substring(chIdx));
      if (chMatch == null) break;
      final absoluteStart = chIdx + chMatch.start;
      final chId = chMatch.group(1)!;
      final blockStart = absoluteStart + chMatch.group(0)!.length;
      final blockEnd = xmlContent.indexOf('</channel>', blockStart);
      final block = blockEnd >= 0
          ? xmlContent.substring(blockStart, blockEnd)
          : '';
      final displayName = displayNameRegex
          .firstMatch(block)
          ?.group(1)
          ?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        channelNames[chId] = displayName;
      }
      chIdx = blockEnd >= 0 ? blockEnd + 10 : absoluteStart + 1;
    }

    final programs = <String, List<EpgProgram>>{};
    final programmeTagRegex = RegExp('<programme\\s+[^>]*?>');
    final attrRegex = RegExp('\\b(start|stop|channel)="([^"]*)"');
    final titleRegex = RegExp('<title>([^<]*)</title>');
    final descRegex = RegExp('<desc>([^<]*)</desc>');
    final iconRegex = RegExp('<icon\\s+src="([^"]+)"');
    const programEndTag = '</programme>';

    var currentIndex = 0;
    while (true) {
      final progTagMatch = programmeTagRegex.firstMatch(
        xmlContent.substring(currentIndex),
      );
      if (progTagMatch == null) break;
      final absStart = currentIndex + progTagMatch.start;
      final tagText = progTagMatch.group(0)!;
      final attrs = <String, String>{};
      for (final m in attrRegex.allMatches(tagText)) {
        attrs[m.group(1)!] = m.group(2)!;
      }
      final startStr = attrs['start'] ?? '';
      final stopStr = attrs['stop'] ?? '';
      final channelId = attrs['channel'] ?? '';

      if (channelId.isEmpty) {
        currentIndex = absStart + tagText.length;
        continue;
      }

      final blockStart = absStart + tagText.length;
      final blockEnd = xmlContent.indexOf(programEndTag, blockStart);
      final block = blockEnd >= 0
          ? xmlContent.substring(blockStart, blockEnd)
          : '';

      final title =
          titleRegex.firstMatch(block)?.group(1)?.trim() ?? 'Unknown';
      final description = descRegex.firstMatch(block)?.group(1)?.trim();
      final icon = iconRegex.firstMatch(block)?.group(1);

      final startTime = parseXmltvDate(startStr);
      final endTime = parseXmltvDate(stopStr);

      if (startTime != null && endTime != null && endTime.isAfter(startTime)) {
        programs.putIfAbsent(channelId, () => []).add(
              EpgProgram(
                channelId: channelId,
                title: title,
                description: description,
                startTime: startTime,
                endTime: endTime,
                icon: icon,
              ),
            );
      }

      currentIndex = blockEnd >= 0
          ? blockEnd + programEndTag.length
          : absStart + tagText.length;
    }

    for (final list in programs.values) {
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    return EpgParseResult(
      programsByChannelId: programs,
      channelDisplayNames: channelNames,
    );
  }

  /// Parses an XMLTV date `YYYYMMDDHHMMSS [+-]HHMM` into a local DateTime.
  static DateTime? parseXmltvDate(String dateStr) {
    final cleaned = dateStr.trim();
    if (cleaned.length < 14) return null;

    String datePart;
    int tzOffsetMinutes;
    final spaceIdx = cleaned.indexOf(' ');
    if (spaceIdx > 0) {
      datePart = cleaned.substring(0, spaceIdx);
      final tzStr = cleaned.substring(spaceIdx).trim();
      tzOffsetMinutes = _parseTimezoneOffset(tzStr);
    } else {
      datePart = cleaned;
      tzOffsetMinutes = 0;
    }

    if (datePart.length < 14) return null;

    try {
      final year = int.parse(datePart.substring(0, 4));
      final month = int.parse(datePart.substring(4, 6));
      final day = int.parse(datePart.substring(6, 8));
      final hour = int.parse(datePart.substring(8, 10));
      final minute = int.parse(datePart.substring(10, 12));
      final second = int.parse(datePart.substring(12, 14));

      final utc = DateTime.utc(year, month, day, hour, minute, second);
      return utc.subtract(Duration(minutes: tzOffsetMinutes)).toLocal();
    } catch (_) {
      return null;
    }
  }

  static int _parseTimezoneOffset(String tz) {
    if (tz.length < 3) return 0;
    final sign = tz.startsWith('-') ? -1 : 1;
    final hours = int.tryParse(tz.substring(1, 3)) ?? 0;
    final minutes = tz.length >= 5 ? int.tryParse(tz.substring(3, 5)) ?? 0 : 0;
    return sign * (hours * 60 + minutes);
  }
}
