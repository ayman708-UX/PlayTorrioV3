import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/iptv/playtorrio_tv/m3u/m3u_parser.dart';

void main() {
  test('parses basic M3U playlist', () {
    const body = '''
#EXTM3U
#EXTINF:-1 tvg-id="bbc.one" tvg-logo="http://logo" group-title="News",BBC One
http://stream.example/bbc.m3u8
''';

    final channels = M3uParser.parse(body);
    expect(channels.length, 1);
    expect(channels.first.name, 'BBC One');
    expect(channels.first.tvgId, 'bbc.one');
    expect(channels.first.url, 'http://stream.example/bbc.m3u8');
  });
}
