import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fvp/fvp.dart' as fvp;

import './pages/home/home_page.dart';
import './services/addon/addon_manager.dart';
import './services/app_updater_service.dart';
import './services/glass_settings.dart';
import './services/my_list/my_list_service.dart';
import './services/trakt/trakt_auth_service.dart';
import './services/trakt/trakt_sync_service.dart';
import './widgets/common/dpad_focus.dart';
import './widgets/update_dialog.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  fvp.registerWith();
  await Future.wait([
    AddonManager.instance.initialize(),
    GlassSettings.initialize(),
    MyListService.initialize(),
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
    DpadNavigation.initialize();
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
    const background = Color(0xFF080A0F);
    const surface = Color(0xFF151822);
    const surfaceLight = Color(0xFF1A1D27);
    const primary = Color(0xFF7C5CFF);
    const gold = Color(0xFFFFD700);
    const cyan = Color(0xFF00F0FF);
    const error = Color(0xFFFFB4AB);

    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF2B1B66),
      onPrimaryContainer: Colors.white,
      secondary: gold,
      onSecondary: Colors.black,
      secondaryContainer: Color(0xFF3A3400),
      onSecondaryContainer: gold,
      tertiary: cyan,
      onTertiary: Colors.black,
      tertiaryContainer: Color(0xFF003C42),
      onTertiaryContainer: cyan,
      error: error,
      onError: Colors.black,
      errorContainer: Color(0xFF3B0A12),
      onErrorContainer: error,
      surface: surface,
      onSurface: Color(0xFFE5E2E1),
      surfaceContainerHighest: surfaceLight,
      onSurfaceVariant: Color(0xFFC1C6D7),
      outline: Color(0xFF414755),
      outlineVariant: Color(0xFF414755),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE5E2E1),
      onInverseSurface: Color(0xFF080A0F),
      inversePrimary: primary,
      surfaceTint: primary,
    );

    const monoText = TextStyle(fontFamily: 'monospace');

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'PlayTorrio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: colorScheme,
        useMaterial3: true,
        // Glass-style surfaces used across IPTVNutz/MultiNutz.
        dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0x33FFFFFF), width: 0.5),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceLight,
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x33FFFFFF), width: 0.5),
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceLight,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surfaceLight,
          selectedColor: primary,
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceLight,
          hintStyle: const TextStyle(color: Color(0x80FFFFFF), fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primary,
        ),
        focusColor: const Color(0xFFFFD700).withValues(alpha: 0.55),
        dividerTheme: const DividerThemeData(
          color: Color(0x1AFFFFFF),
          thickness: 0.5,
        ),
        textTheme: const TextTheme(
          // Display/headline stack (Sora-equivalent via system sans fallback)
          displayLarge: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
          headlineMedium: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
          bodySmall: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
          labelSmall: monoText,
          labelMedium: monoText,
        ),
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        overscroll: false,
      ),
      home: const HomePage(),
    );
  }
}

