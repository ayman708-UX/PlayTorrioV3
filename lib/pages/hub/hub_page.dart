import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_hub.dart';
import '../../widgets/common/nested_navigator.dart';
import '../../widgets/common/universal_play_bar.dart';
import '../../utils/hub_controller.dart';
import '../../utils/hub_navigator.dart';
import '../../utils/route_transitions.dart';
import '../../widgets/common/top_bar.dart';
import '../settings/settings_page.dart';
import 'media_hub.dart';
import 'books_hub.dart';
import 'music_hub.dart';

/// HubPage: the top-level container hosting all primary app hubs
/// (Media, Books, Music) in an IndexedStack. Each hub owns its own sidebar
/// (hub switcher, sections, search, settings) — there's no shared header.
class HubPage extends StatefulWidget {
  const HubPage({Key? key}) : super(key: key);

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  final FocusNode _focusNode = FocusNode();

  // Each hub is lazily wrapped in its own nested Navigator the first time it's
  // shown, so offstage hubs are not laid out at startup (which can crash pages
  // that assume a non-zero width, and stalls first paint with eager network).
  static const List<Widget Function()> _hubBuilders = [
    _buildMediaHub,
    _buildBooksHub,
    _buildMusicHub,
  ];
  final List<Widget?> _built = List<Widget?>.filled(3, null);

  static Widget _buildMediaHub() => const NestedNavigator(child: MediaHub());
  static Widget _buildBooksHub() => const NestedNavigator(child: BooksHub());
  static Widget _buildMusicHub() => const NestedNavigator(child: MusicHub());

  // Intro animation state
  static bool _hasShownIntro = false;
  late bool _showIntro;

  void _setHub(AppHub hub) {
    HubController.instance.setHub(hub);
  }

  @override
  void initState() {
    super.initState();
    _showIntro = !_hasShownIntro;
    _hasShownIntro = true;

    // Allow child hub pages to navigate back to the primary media hub.
    HubNavigator.registerGoHome(() => _setHub(AppHub.media));

    if (_showIntro) {
      _playIntro();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// TV remote Back/Exit support: Escape pops the current route.
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // Only pop if there is actually a route to pop. On the root HubPage
      // there is nothing beneath it, so popping would leave a black screen.
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _playIntro() async {
    // Show intro for 1.8 seconds so it feels fast
    await Future.delayed(const Duration(milliseconds: 1800));

    if (mounted) {
      setState(() => _showIntro = false);
    }
  }

  static const double _topBarHeight = 60;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A0F),
        body: Stack(
          children: [
            // Global top bar: only the logo + Watch/Listen/Read switcher.
            // It sits at the very top so the icon stays visible; the content
            // below is pushed down by the bar's own height.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: TopBar(
                height: _topBarHeight,
                onSettingsTap: () => Navigator.push(
                  context,
                  LiquidRevealRoute(
                    page: const SettingsPage(),
                    tapPosition: null,
                  ),
                ),
              ),
            ),
            // Content box: each hub renders its own left sidebar, so this
            // spans the full width, starting below the shared top bar.
            Positioned(
              top: topPadding + _topBarHeight,
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                ),
                child: ListenableBuilder(
                  listenable: HubController.instance,
                  builder: (context, _) {
                    final index = HubController.instance.currentHub.index;
                    // Lazily materialize the active hub on first show.
                    if (_built[index] == null) {
                      _built[index] = _hubBuilders[index]();
                    }
                    return IndexedStack(
                      index: index,
                      children: [
                        _built[0] ?? const SizedBox.shrink(),
                        _built[1] ?? const SizedBox.shrink(),
                        _built[2] ?? const SizedBox.shrink(),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Universal Play Bar (hidden during intro)
            // On desktop it sits above the bottom, offset right of the left
            // sidebar (collapsed when the sidebar rail shrinks); on mobile it
            // sits above the bottom section nav.
            if (!_showIntro)
              Positioned(
                bottom: isDesktop ? 16 : 76,
                left: 12,
                right: 12,
                child: ListenableBuilder(
                  listenable: HubController.instance,
                  builder: (context, _) {
                    // The play bar only applies to the Listen hub.
                    if (HubController.instance.currentHub != AppHub.music) {
                      return const SizedBox.shrink();
                    }
                    return const UniversalPlayBar();
                  },
                ),
              ),
            // Intro Splash Screen
            Positioned.fill(child: _buildIntroOverlay(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroOverlay(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final titleSize = (screenWidth * 0.08).clamp(40.0, 56.0);
    final subtitleSize = (screenWidth * 0.03).clamp(16.0, 20.0);
    final iconSize = (screenWidth * 0.12).clamp(48.0, 72.0);

    return IgnorePointer(
      ignoring: !_showIntro,
      child: AnimatedOpacity(
        opacity: _showIntro ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        child: Container(
          color: const Color(0xFF080A0F),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/icon.png',
                  width: iconSize * 1.5,
                  height: iconSize * 1.5,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 32),
                Text(
                  'PlayTorrio',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your Cinema Universe',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: subtitleSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white54,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
