import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/stream/stream_model.dart';
import 'package:playtorrio/services/stream/stream_bitrate_resolver.dart';

void main() {
  group('StreamBitrateResolver Tests', () {
    late HttpServer testServer;
    late int serverPort;
    int masterHits = 0;

    setUpAll(() async {
      testServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = testServer.port;

      testServer.listen((request) async {
        final path = request.uri.path;

        if (path == '/master.m3u8') {
          masterHits++;
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl')
            ..write(
                '#EXTM3U\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=2120000,RESOLUTION=960x540\n'
                'v540.m3u8\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=4864000,RESOLUTION=1280x720\n'
                'v720.m3u8\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=15480000,RESOLUTION=1920x1080\n'
                'v1080.m3u8\n');
          await request.response.close();
        } else if (path == '/media.m3u8') {
          // Media playlist, no variant info to read
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl')
            ..write('#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:10.0,\nsegment1.ts\n');
          await request.response.close();
        } else if (path == '/movie.mp4') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'video/mp4')
            ..write('not a manifest');
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found');
          await request.response.close();
        }
      });
    });

    tearDownAll(() async {
      await testServer.close();
    });

    test('parseManifestKbps picks the highest variant', () {
      const manifest = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1000000\na.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=8000000\nb.m3u8\n';
      expect(StreamBitrateResolver.parseManifestKbps(manifest), 8000);
    });

    test('parseManifestKbps returns null for media playlists', () {
      expect(StreamBitrateResolver.parseManifestKbps('#EXTM3U\n#EXTINF:10.0,\nseg.ts\n'), isNull);
    });

    test('resolves peak bitrate from an HLS master playlist', () async {
      final source = StreamSource(
        addonName: 'TestAddon',
        name: 'Direct',
        url: 'http://127.0.0.1:$serverPort/master.m3u8',
      );
      expect(await StreamBitrateResolver.resolveKbps(source), 15480);
    });

    test('caches manifest lookups per url', () async {
      final source = StreamSource(
        addonName: 'TestAddon',
        name: 'Direct',
        url: 'http://127.0.0.1:$serverPort/master.m3u8',
      );
      final hitsBefore = masterHits;
      await StreamBitrateResolver.resolveKbps(source);
      await StreamBitrateResolver.resolveKbps(source);
      expect(masterHits, hitsBefore);
    });

    test('returns null for media playlists without variants', () async {
      final source = StreamSource(
        addonName: 'TestAddon',
        name: 'Direct',
        url: 'http://127.0.0.1:$serverPort/media.m3u8',
      );
      expect(await StreamBitrateResolver.resolveKbps(source), isNull);
    });

    test('does not treat non-playlist responses as manifests', () async {
      final source = StreamSource(
        addonName: 'TestAddon',
        name: 'Direct',
        url: 'http://127.0.0.1:$serverPort/movie.mp4',
      );
      expect(await StreamBitrateResolver.resolveKbps(source), isNull);
    });

    test('ignores magnet sources', () async {
      final source = StreamSource(
        addonName: 'Torrentio',
        name: 'Torrent',
        infoHash: 'abcdef0123456789',
        url: 'magnet:?xt=urn:btih:abcdef0123456789',
      );
      expect(await StreamBitrateResolver.resolveKbps(source), isNull);
    });

    test('returns null for unreachable urls', () async {
      final source = StreamSource(
        addonName: 'TestAddon',
        name: 'Direct',
        url: 'http://127.0.0.1:$serverPort/dead_404.m3u8',
      );
      expect(await StreamBitrateResolver.resolveKbps(source), isNull);
    });
  });
}
