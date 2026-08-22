import 'package:flutter/material.dart';

import '../../pages/search/search_page.dart';
import '../../utils/route_transitions.dart';

/// A small search icon button meant for each catalog/section page's own
/// title row. Replaces the old global header search bar — search is now
/// scoped to whatever page it's pressed from (via [SearchScope]).
class PageSearchButton extends StatelessWidget {
  const PageSearchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Search',
      icon: Icon(
        Icons.search_rounded,
        color: Colors.white.withValues(alpha: 0.75),
      ),
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        final offset = box != null
            ? box.localToGlobal(box.size.center(Offset.zero))
            : null;
        Navigator.push(
          context,
          LiquidRevealRoute(page: const SearchPage(), tapPosition: offset),
        );
      },
    );
  }
}
