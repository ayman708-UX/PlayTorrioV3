import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/playback/playback_history_item.dart';
import 'package:playtorrio/services/playback/playback_history_service.dart';

void main() {
  group('PlaybackHistoryService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      PlaybackHistoryService.history.value = [];
      await PlaybackHistoryService.initialize();
    });

    test('saveProgress adds and updates playback timestamps', () {
      final item = PlaybackHistoryItem(
        id: 'tt0137523',
        title: 'Fight Club',
        position: const Duration(minutes: 45),
        duration: const Duration(minutes: 139),
        lastWatched: DateTime.now(),
      );

      PlaybackHistoryService.saveProgress(item);
      expect(PlaybackHistoryService.history.value.length, 1);
      expect(PlaybackHistoryService.getProgress('tt0137523')?.position.inMinutes, 45);

      final updated = item.copyWith(position: const Duration(minutes: 90));
      PlaybackHistoryService.saveProgress(updated);
      expect(PlaybackHistoryService.history.value.length, 1);
      expect(PlaybackHistoryService.getProgress('tt0137523')?.position.inMinutes, 90);
    });

    test('removeProgress deletes item from history', () {
      final item = PlaybackHistoryItem(
        id: 'tt0137523',
        title: 'Fight Club',
        position: const Duration(minutes: 45),
        duration: const Duration(minutes: 139),
        lastWatched: DateTime.now(),
      );

      PlaybackHistoryService.saveProgress(item);
      expect(PlaybackHistoryService.history.value.isNotEmpty, isTrue);

      PlaybackHistoryService.removeProgress('tt0137523');
      expect(PlaybackHistoryService.history.value, isEmpty);
    });
  });
}
