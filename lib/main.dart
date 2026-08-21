import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fvp/fvp.dart' as fvp;

import './pages/home/home_page.dart';
import './pages/hub/hub_page.dart';

// Feature flag for staged rollout of HubPage refactor. Set to true to enable the
// HubPage container (IndexedStack). Keep false to preserve the previous
// single-HomePage behavior.
const bool enableHubPage = true;
import './services/addon/addon_manager.dart';
import './services/app_updater_service.dart';
import './services/debrid/debrid_service.dart';
import './services/download/download_service.dart';
import './services/glass_settings.dart';
import './services/my_list/my_list_service.dart';
import './services/playback/playback_history_service.dart';
import './services/trakt/trakt_auth_service.dart';
import './services/trakt/trakt_sync_service.dart';
import './widgets/update_dialog.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  fvp.registerWith();
  await Future.wait([
    AddonManager.instance.initialize(),
    DebridService.instance.initialize(),
    DownloadService.initialize(),
    GlassSettings.initialize(),
    MyListService.initialize(),
    PlaybackHistoryService.initialize(),
    TraktAuthService().initialize(),
    TraktSyncService.initialize(),
  ]);
  runApp(const PlayTorrioApp());
}

class PlayTorrioApp extends StatefulWidget {
  const PlayTorrioApp({super.key});

  @override
  State<PlayTorrioApp> createState() => _PlayTorrioAppState();
}

class _PlayTorrioAppState extends State<PlayTorrioApp>
    with WidgetsBindingObserver {
  static bool _hasCheckedInitialUpdate = false;
  static bool _isShowingUpdateDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedInitialUpdate) {
        _hasCheckedInitialUpdate = true;
        _checkForUpdates();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isShowingUpdateDialog) return;
    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();
      final context = navigatorKey.currentContext;

      if (updateInfo != null && context != null && context.mounted) {
        _isShowingUpdateDialog = true;
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
        _isShowingUpdateDialog = false;
      }
    } catch (e) {
      _isShowingUpdateDialog = false;
      debugPrint('Error checking for app updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'PlayTorrio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080A0F),
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7C5CFF),
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        overscroll: false,
      ),
      home: enableHubPage ? const HubPage() : const HomePage(),
    );
  }
}

