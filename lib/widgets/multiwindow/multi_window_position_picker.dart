import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/iptv/multi_window_store.dart';

/// Bottom-sheet slot picker for "Add to MultiWindow" (mirrors
/// `MultiWindowPositionPicker.kt`). Shows all 6/9 slots with occupancy.
class MultiWindowPositionPicker extends StatefulWidget {
  const MultiWindowPositionPicker({
    super.key,
    this.channelName,
    this.channelLogo,
    this.streamTitle,
    this.streamPoster,
    this.selectionMode = false,
    required this.onSlotSelected,
    this.onSlotSelectedAndOpenHub,
  });

  final String? channelName;
  final String? channelLogo;
  final String? streamTitle;
  final String? streamPoster;
  final bool selectionMode;
  final ValueChanged<int> onSlotSelected;
  final ValueChanged<int>? onSlotSelectedAndOpenHub;

  /// Presents the picker as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? channelName,
    String? channelLogo,
    String? streamTitle,
    String? streamPoster,
    bool selectionMode = false,
    required ValueChanged<int> onSlotSelected,
    ValueChanged<int>? onSlotSelectedAndOpenHub,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => MultiWindowPositionPicker(
        channelName: channelName,
        channelLogo: channelLogo,
        streamTitle: streamTitle,
        streamPoster: streamPoster,
        selectionMode: selectionMode,
        onSlotSelected: onSlotSelected,
        onSlotSelectedAndOpenHub: onSlotSelectedAndOpenHub,
      ),
    );
  }

  @override
  State<MultiWindowPositionPicker> createState() =>
      _MultiWindowPositionPickerState();
}

class _MultiWindowPositionPickerState extends State<MultiWindowPositionPicker> {
  int? _selectedSlot;

  @override
  Widget build(BuildContext context) {
    final store = MultiWindowStore.instance;
    final displayTitle = widget.channelName ?? widget.streamTitle ?? 'Unknown';
    final displayLogo = widget.channelLogo ?? widget.streamPoster;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF080A0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Colors.white12, width: 0.6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (displayLogo != null && displayLogo.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: displayLogo,
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add to MultiWindow',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                final isTablet = box.maxWidth >= 600;
                final slotCount =
                    isTablet ? MultiWindowStore.maxSlots : 6;
                return _slotGrid(
                  store: store,
                  slotCount: slotCount,
                  boxWidth: box.maxWidth,
                );
              },
            ),
            if (widget.selectionMode) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      enabled: _selectedSlot != null,
                      label: 'Add to Slot',
                      onTap: () {
                        final slot = _selectedSlot;
                        if (slot != null) widget.onSlotSelected(slot);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      enabled: _selectedSlot != null,
                      label: 'Add & Open Hub',
                      accent: true,
                      onTap: () {
                        final slot = _selectedSlot;
                        if (slot != null) {
                          widget.onSlotSelectedAndOpenHub?.call(slot);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _slotGrid({
    required MultiWindowStore store,
    required int slotCount,
    required double boxWidth,
  }) {
    const columns = 3;
    final rows = (slotCount / columns).ceil();
    const spacing = 10.0;
    final cellWidth = (boxWidth - (spacing * (columns - 1))) / columns;

    return Column(
      children: List.generate(rows, (row) {
        final start = row * columns;
        final rowSlots = [
          for (var c = 0; c < columns; c++)
            if (start + c < slotCount) start + c,
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: spacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, slot) in rowSlots.indexed) ...[
                if (i > 0) const SizedBox(width: spacing),
                SizedBox(
                  width: cellWidth,
                  child: _SlotCell(
                    slot: slot,
                    store: store,
                    isSelected: _selectedSlot == slot,
                    onTap: () {
                      if (widget.selectionMode) {
                        setState(() {
                          _selectedSlot = _selectedSlot == slot ? null : slot;
                        });
                      } else {
                        widget.onSlotSelected(slot);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _SlotCell extends StatelessWidget {
  final int slot;
  final MultiWindowStore store;
  final bool isSelected;
  final VoidCallback onTap;

  const _SlotCell({
    required this.slot,
    required this.store,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final existing = store.streamForSlot(slot);
    final isOccupied = existing != null;

    final Border? border;
    if (isSelected) {
      border = Border.all(color: const Color(0xFF7C5CFF), width: 2);
    } else if (isOccupied) {
      border = Border.all(
        color: const Color(0xFF7C5CFF).withValues(alpha: 0.3),
        width: 1,
      );
    } else {
      border = null;
    }

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? const Color(0xFF7C5CFF).withValues(alpha: 0.25)
                : isOccupied
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFF111111),
            border: border,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOccupied) ...[
                if (existing.poster != null && existing.poster!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: existing.poster!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  existing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Slot ${slot + 1}',
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 8,
                  ),
                ),
              ] else ...[
                Text(
                  'Slot ${slot + 1}',
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Empty',
                  style: TextStyle(
                    color: const Color(0xFFB0B0B0).withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool enabled;
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _ActionButton({
    required this.enabled,
    required this.label,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = const Color(0xFF7C5CFF);
    final color = enabled
        ? accent
            ? base.withValues(alpha: 0.8)
            : base
        : base.withValues(alpha: 0.3);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: enabled ? 1 : 0.4),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}