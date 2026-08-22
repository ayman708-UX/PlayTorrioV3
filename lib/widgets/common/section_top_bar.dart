import 'package:flutter/material.dart';

import '../../utils/hub_controller.dart';

/// A horizontal bar of section chips shown at the top of each hub's content
/// area. Mirrors the sidebar's section items so sections are reachable from the
/// content even when the sidebar is collapsed.
///
/// The chips are driven by [HubController.currentSections] so they stay in sync
/// with the active hub and sidebar selection.
class SectionTopBar extends StatelessWidget {
  const SectionTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0E17),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: ListenableBuilder(
        listenable: HubController.instance,
        builder: (context, _) {
          final sections = HubController.instance.currentSections;
          final activeId = HubController.instance.currentSectionId;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final section = sections[index];
              final isSelected = section.id == activeId;
              return _Chip(
                label: section.label,
                icon: section.icon,
                selected: isSelected,
                onTap: () =>
                    HubController.instance.setCurrentSection(section.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF7C5CFF).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? const Color(0xFF7C5CFF) : Colors.white60,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}