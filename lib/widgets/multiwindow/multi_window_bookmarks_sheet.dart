import 'package:flutter/material.dart';

import '../../models/multiwindow/multi_window_models.dart';

const _bg = Color(0xFF080A0F);
const _onSurface = Color(0xFFE0E0E0);
const _onSurfaceVariant = Color(0xFFB0B0B0);
const _surfaceCard = Color(0xFF1A1A1A);
const _surfaceLow = Color(0xFF111111);
const _accent = Color(0xFF7C5CFF);
const _red = Color(0xFFFF4444);

/// Bookmarks manager sheet (mirrors `MultiWindowBookmarksSheet` in
/// `MultiWindowBookmarks.kt`).
class MultiWindowBookmarksSheet extends StatefulWidget {
  const MultiWindowBookmarksSheet({
    super.key,
    required this.bookmarks,
    required this.onSave,
    required this.onLoad,
    required this.onDelete,
  });

  final List<MultiWindowBookmark> bookmarks;
  final ValueChanged<String> onSave;
  final ValueChanged<MultiWindowBookmark> onLoad;
  final ValueChanged<String> onDelete;

  static Future<void> show(
    BuildContext context, {
    required List<MultiWindowBookmark> bookmarks,
    required ValueChanged<String> onSave,
    required ValueChanged<MultiWindowBookmark> onLoad,
    required ValueChanged<String> onDelete,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => MultiWindowBookmarksSheet(
        bookmarks: bookmarks,
        onSave: onSave,
        onLoad: onLoad,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<MultiWindowBookmarksSheet> createState() =>
      _MultiWindowBookmarksSheetState();
}

class _MultiWindowBookmarksSheetState extends State<MultiWindowBookmarksSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white12, width: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Bookmarks',
                  style: TextStyle(
                    color: _onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  '${widget.bookmarks.length}',
                  style: const TextStyle(color: _onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _promptSaveName(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Save Current Layout',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0x26FFFFFF), height: 1),
            const SizedBox(height: 8),
            if (widget.bookmarks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No bookmarks yet',
                  style: TextStyle(color: _onSurfaceVariant, fontSize: 14),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.bookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final bm = widget.bookmarks[index];
                    return GestureDetector(
                      onTap: () => _promptLoad(bm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceCard,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bm.name,
                                    style: const TextStyle(
                                      color: _onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '${bm.slotChannels.length} streams',
                                        style: const TextStyle(
                                          color: _onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '•',
                                        style: TextStyle(
                                          color: _onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        bm.layoutName ?? 'Auto',
                                        style: const TextStyle(
                                          color: _onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => widget.onDelete(bm.id),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _surfaceLow,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '✕',
                                  style: TextStyle(
                                    color: _red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _promptSaveName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: _surfaceCard,
          title: const Text(
            'Save Bookmark',
            style: TextStyle(
              color: _onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: _onSurface),
            decoration: const InputDecoration(
              labelText: 'Bookmark name',
              labelStyle: TextStyle(color: _onSurfaceVariant),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text(
                'Save',
                style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    widget.onSave(name);
  }

  Future<void> _promptLoad(MultiWindowBookmark bm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surfaceCard,
        title: const Text(
          'Load Layout',
          style: TextStyle(
            color: _onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Replace current grid with "${bm.name}"?',
          style: const TextStyle(color: _onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Replace',
              style: TextStyle(color: _accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onLoad(bm);
  }
}