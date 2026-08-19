import '../../models/iptv/iptv_models.dart';

/// Port of `M3uParser.kt` — parses M3U playlist content into channels.
class M3uParser {
  static List<IptvChannel> parse(String content, String sourceId) {
    final channels = <IptvChannel>[];
    final lines = content.split('\n');
    var i = 0;

    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.startsWith('#EXTINF:')) {
        final infoLine = line.substring('#EXTINF:'.length);

        final tvgId = _extractTag(infoLine, 'tvg-id');
        final tvgName = _extractTag(infoLine, 'tvg-name');
        final tvgLogo = _extractTag(infoLine, 'tvg-logo');
        final groupTitle = _extractTag(infoLine, 'group-title');

        final commaIndex = infoLine.lastIndexOf(',');
        final channelName = commaIndex >= 0
            ? infoLine.substring(commaIndex + 1).trim()
            : 'Unknown';

        i++;
        while (i < lines.length && lines[i].trim().isEmpty) {
          i++;
        }

        if (i < lines.length) {
          final url = lines[i].trim();
          if (url.isNotEmpty && !url.startsWith('#')) {
            final id = tvgId.isNotEmpty ? tvgId : url;
            channels.add(
              IptvChannel(
                id: id,
                name: tvgName.isNotEmpty ? tvgName : channelName,
                logo: tvgLogo.isNotEmpty ? tvgLogo : null,
                group: groupTitle.isNotEmpty ? groupTitle : null,
                url: url,
                epgChannelId: tvgId.isNotEmpty ? tvgId : null,
                sourceType: SourceType.m3u,
                sourceId: sourceId,
              ),
            );
          }
        }
      }
      i++;
    }
    return channels;
  }

  static String _extractTag(String line, String tag) {
    final regex = RegExp('$tag="([^"]*)"');
    final match = regex.firstMatch(line);
    return match?.group(1)?.trim() ?? '';
  }
}
