import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/torbox/torbox_service.dart';

void main() {
  group('TorBoxService', () {
    late TorBoxService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = TorBoxService();
      await service.initialize();
    });

    test('starts unconfigured', () {
      expect(service.isConfigured.value, false);
      expect(service.apiKey, isNull);
    });

    test('setApiKey persists and marks configured', () async {
      await service.setApiKey('test-key-123');
      expect(service.isConfigured.value, true);
      expect(service.apiKey, 'test-key-123');

      final reloaded = TorBoxService();
      await reloaded.initialize();
      expect(reloaded.apiKey, 'test-key-123');
      expect(reloaded.isConfigured.value, true);
    });

    test('clearApiKey removes configuration', () async {
      await service.setApiKey('test-key-123');
      await service.clearApiKey();
      expect(service.isConfigured.value, false);
      expect(service.apiKey, isNull);
    });
  });

  group('TorBoxFileSelector', () {
    final selector = TorBoxFileSelector.instance;

    test('selects preferred file index', () {
      final id = selector.selectFileId(
        [
          {'id': 1, 'name': 'sample.mkv', 'size': 1000},
          {'id': 2, 'name': 'sample2.mkv', 'size': 2000},
        ],
        preferredIdx: 1,
      );
      expect(id, 1);
    });

    test('selects episode file for series', () {
      final id = selector.selectFileId(
        [
          {'id': 1, 'name': 'Show.S01E01.1080p.mkv', 'size': 1000},
          {'id': 2, 'name': 'Show.S01E02.1080p.mkv', 'size': 1000},
        ],
        season: 1,
        episode: 2,
      );
      expect(id, 2);
    });

    test('selects largest media file by default', () {
      final id = selector.selectFileId(
        [
          {'id': 1, 'name': 'movie.720p.mkv', 'size': 1000},
          {'id': 2, 'name': 'movie.1080p.mkv', 'size': 5000},
          {'id': 3, 'name': 'readme.txt', 'size': 99999},
        ],
      );
      expect(id, 2);
    });
  });
}
