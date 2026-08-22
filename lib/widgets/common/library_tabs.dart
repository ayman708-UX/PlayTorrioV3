import 'package:flutter/material.dart';

/// A reusable tabbed "Library" scaffold shared by the Media, Music, and Books
/// hubs so they all present their library content with a consistent design.
///
/// Each hub supplies its own [tabs]; the widget renders a header with the
/// [title] and a [TabBar] + [TabBarView] with the same visual language.
class LibraryTabs extends StatefulWidget {
  final String title;
  final IconData titleIcon;
  final List<LibraryTab> tabs;
  final int initialIndex;
  final Widget? trailing;

  const LibraryTabs({
    super.key,
    required this.title,
    required this.titleIcon,
    required this.tabs,
    this.initialIndex = 0,
    this.trailing,
  });

  @override
  State<LibraryTabs> createState() => _LibraryTabsState();
}

class _LibraryTabsState extends State<LibraryTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex: widget.initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.titleIcon, color: const Color(0xFF7C5CFF), size: 22),
            const SizedBox(width: 10),
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ],
        ),
        actions: [
          if (widget.trailing != null) widget.trailing!,
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: widget.tabs.length > 4,
          indicatorColor: const Color(0xFF7C5CFF),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: widget.tabs
              .map((t) => Tab(icon: Icon(t.icon, size: 17), text: t.label))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: widget.tabs.map((t) => t.builder(context)).toList(),
      ),
    );
  }
}

/// A single tab within a [LibraryTabs].
class LibraryTab {
  final String label;
  final IconData icon;
  final Widget Function(BuildContext) builder;

  const LibraryTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}

/// A shared empty-state used across library tabs.
class LibraryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const LibraryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}
