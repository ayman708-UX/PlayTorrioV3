import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/models/my_list/my_list_item.dart';
import 'package:playtorrio/models/download/download_item.dart';
import 'package:playtorrio/services/my_list/my_list_service.dart';
import 'package:playtorrio/services/download/download_service.dart';
import 'package:playtorrio/pages/collection/collection_page.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('CollectionPage', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      MyListService.items.value = [];
      DownloadService.downloads.value = [];
      await MyListService.initialize();
      await DownloadService.initialize();
    });

    testWidgets('shows tabs and empty state for My List', (tester) async {
      await tester.pumpWidget(wrap(const CollectionPage()));
      await tester.pumpAndSettle();
      expect(find.text('My List'), findsWidgets);
      expect(find.text('Watchlist'), findsWidgets);
      expect(find.text('History'), findsWidgets);
      expect(find.text('Downloads'), findsWidgets);
      expect(find.text('Your list is empty'), findsOneWidget);
    });

    testWidgets('shows items in My List when populated', (tester) async {
      MyListService.add(MyListItem(traktId: 1, title: 'Inception', year: 2010, type: 'movie', addedAt: DateTime(2026)));
      MyListService.add(MyListItem(traktId: 2, title: 'Interstellar', year: 2014, type: 'movie', addedAt: DateTime(2026)));

      await tester.pumpWidget(wrap(const CollectionPage()));
      await tester.pumpAndSettle();
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('Interstellar'), findsOneWidget);
    });

    testWidgets('shows downloads tab content', (tester) async {
      DownloadService.addDownload(DownloadItem(
        id: 'dl-1',
        title: 'Cyberpunk Edgerunners',
        downloadUrl: 'https://example.com/video.mp4',
        progress: 0.5,
        status: DownloadStatus.downloading,
        createdAt: DateTime.now(),
      ));

      await tester.pumpWidget(wrap(const CollectionPage(initialTabIndex: 3)));
      await tester.pumpAndSettle();
      expect(find.text('Cyberpunk Edgerunners'), findsOneWidget);
      expect(find.text('DOWNLOADING • 50%'), findsOneWidget);
    });
  });
}
