import 'package:flutter/material.dart';

import '../../utils/search_scope.dart';
import '../music/music_page.dart';

/// Music hub: Music, Radio, and Library.
///
/// The Music page already provides its own left sidebar (Home / Browse /
/// Radio / Library) and mobile bottom nav, so this hub simply hosts it.
class MusicHub extends StatelessWidget {
  const MusicHub({super.key});

  @override
  Widget build(BuildContext context) {
    SearchScope.set('music', label: 'Music');
    return const MusicPage();
  }
}
