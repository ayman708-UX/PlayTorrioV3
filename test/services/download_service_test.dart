import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/download/download_item.dart';
import 'package:playtorrio/services/download/download_service.dart';

void main() {
  group('DownloadService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      DownloadService.downloads.value = [];
      await DownloadService.initialize();
    });

    test('addDownload adds items to the list', () {
      final item = DownloadItem(
        id: '1',
        title: 'Arcane',
        downloadUrl: 'https://example.com/ep1.mp4',
        createdAt: DateTime.now(),
      );

      DownloadService.addDownload(item);
      expect(DownloadService.downloads.value.length, 1);
      expect(DownloadService.downloads.value.first.title, 'Arcane');
    });

    test('updateProgress updates progress and status correctly', () {
      final item = DownloadItem(
        id: '1',
        title: 'Arcane',
        downloadUrl: 'https://example.com/ep1.mp4',
        createdAt: DateTime.now(),
      );

      DownloadService.addDownload(item);
      DownloadService.updateProgress('1', 0.8, 800, 1000, DownloadStatus.downloading);

      final updated = DownloadService.downloads.value.first;
      expect(updated.progress, 0.8);
      expect(updated.receivedBytes, 800);
      expect(updated.totalBytes, 1000);
      expect(updated.status, DownloadStatus.downloading);
    });

    test('pause, resume, and remove download', () {
      final item = DownloadItem(
        id: '1',
        title: 'Arcane',
        downloadUrl: 'https://example.com/ep1.mp4',
        createdAt: DateTime.now(),
      );

      DownloadService.addDownload(item);
      DownloadService.pauseDownload('1');
      expect(DownloadService.downloads.value.first.status, DownloadStatus.paused);

      DownloadService.resumeDownload('1');
      expect(DownloadService.downloads.value.first.status, DownloadStatus.downloading);

      DownloadService.removeDownload('1');
      expect(DownloadService.downloads.value, isEmpty);
    });
  });
}
