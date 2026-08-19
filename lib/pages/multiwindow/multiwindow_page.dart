import 'package:flutter/material.dart';

import '../../models/iptv/iptv_models.dart';
import '../../models/multiwindow/multi_window_models.dart';
import '../../models/stream/stream_model.dart';
import '../../services/iptv/iptv_repository.dart';
import '../../services/iptv/multi_window_bookmarks.dart';
import '../../services/iptv/multi_window_player_engine.dart';
import '../../services/iptv/multi_window_store.dart';
import '../../services/iptv/quick_channel_list.dart';
import '../../services/iptv/stream_validation_store.dart';
import '../../widgets/multiwindow/multi_window_bookmarks_sheet.dart';
import '../../widgets/multiwindow/multi_window_cell_options.dart';
import '../../widgets/multiwindow/multi_window_grid.dart';
import '../player/player_screen.dart';

/// The MultiNutz tab: a reactive multi-window video grid (mirrors
/// `RobbdeezeNutzHubScreen.kt`'s MultiNutz surface).
class MultiWindowPage extends StatelessWidget {
  const MultiWindowPage({super.key});

  void _playFullscreen(BuildContext context, WindowStream stream) {
    final url = stream.url;
    if (url == null || url.isEmpty) return;
    final source = StreamSource(
      url: url,
      name: stream.title,
      title: stream.title,
      addonName: 'MultiNutz',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(source: source, title: stream.title),
      ),
    );
  }

  Future<void> _openCellOptions(
    BuildContext context,
    WindowStream stream,
  ) async {
    final store = MultiWindowStore.instance;
    await MultiWindowCellOptionsSheet.show(
      context,
      stream: stream,
      volume: store.getVolume(stream.id),
      onVolumeChange: (vol) {
        store.setVolume(stream.id, vol);
        MultiWindowPlayerManager.instance.setVolume(stream.id, vol);
      },
      onSwap: (target) => store.swapSlots(stream.slotIndex, target),
      onRefresh: () {
        MultiWindowPlayerManager.instance.releasePlayer(stream.id);
      },
      onFullscreen: () => _playFullscreen(context, stream),
      onClose: () => store.remove(stream.id),
    );
  }

  Future<void> _openBookmarks(BuildContext context) async {
    final bookmarkStore = MultiWindowBookmarkStore.instance;
    await bookmarkStore.ensureLoaded();
    if (!context.mounted) return;
    await MultiWindowBookmarksSheet.show(
      context,
      bookmarks: bookmarkStore.bookmarks.value,
      onSave: (name) => bookmarkStore.save(name),
      onLoad: (bm) => bookmarkStore.load(bm),
      onDelete: (id) => bookmarkStore.delete(id),
    );
  }

  Future<void> _openQuickChannels(BuildContext context) async {
    await QuickChannelsSheet.show(context, onAddToSlot: (ch, slot) {
      MultiWindowStore.instance.addToSlot(ch, slot);
    });
  }

  Future<void> _browseChannels(BuildContext context) async {
    final store = MultiWindowStore.instance;
    await MultiWindowChannelPickerSheet.show(
      context,
      onSelect: (ch) {
        final slot = store.nextAvailableSlot() ?? 0;
        store.addToSlot(ch, slot);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = MultiWindowStore.instance;
    final bookmarkStore = MultiWindowBookmarkStore.instance;

    return ValueListenableBuilder<List<WindowStream>>(
      valueListenable: store.streams,
      builder: (context, streams, _) {
        return Column(
          children: [
            Expanded(
              child: MultiWindowGrid(
                streams: streams,
                onRemoveStream: (id) => store.remove(id),
                onAddMore: () => _browseChannels(context),
                onCellLongPress: (stream) => _openCellOptions(context, stream),
                onCellVolumeToggle: (stream, active) {
                  final vol = active ? 1.0 : 0.0;
                  MultiWindowPlayerManager.instance.setVolume(stream.id, vol);
                },
                onBookmarksClick: () => _openBookmarks(context),
                onQuickChannelsClick: () => _openQuickChannels(context),
                onMuteAll: () {
                  final allMuted = streams.every(
                    (s) => store.getVolume(s.id) == 0,
                  );
                  for (final s in streams) {
                    final vol = allMuted ? 1.0 : 0.0;
                    store.setVolume(s.id, vol);
                    MultiWindowPlayerManager.instance.setVolume(s.id, vol);
                  }
                  if (allMuted && streams.isNotEmpty) {
                    MultiWindowPlayerManager.instance
                        .setAudioFocus(streams.first.id);
                    store.setAudioFocus(streams.first.id);
                  }
                },
                onCloseAll: () {
                  MultiWindowPlayerManager.instance.releaseAll();
                  store.clear();
                },
                onPauseAll: () {
                  final allPaused =
                      streams.every((s) => store.isPaused(s.id));
                  for (final s in streams) {
                    store.setPaused(s.id, !allPaused);
                    if (allPaused) {
                      MultiWindowPlayerManager.instance.resumePlayer(s.id);
                    } else {
                      MultiWindowPlayerManager.instance.pausePlayer(s.id);
                    }
                  }
                },
                onRefreshAll: () {
                  for (final s in streams) {
                    MultiWindowPlayerManager.instance.releasePlayer(s.id);
                  }
                },
                onFullscreenCell: (stream) =>
                    _playFullscreen(context, stream),
              ),
            ),
            // Bookmarks count footer (reactive)
            ValueListenableBuilder<List<MultiWindowBookmark>>(
              valueListenable: bookmarkStore.bookmarks,
              builder: (context, bookmarks, _) {
                if (bookmarks.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${bookmarks.length} saved layout${bookmarks.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Entry used by the cell options quick overlay (mirrors `QuickChannelsSheet`).
class QuickChannelsSheet {
  static Future<void> show(
    BuildContext context, {
    required void Function(IptvChannel channel, int slot) onAddToSlot,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => _QuickChannelsBottomSheet(
        onAddToSlot: onAddToSlot,
      ),
    );
  }
}

class _QuickChannelsBottomSheet extends StatelessWidget {
  final void Function(IptvChannel channel, int slot) onAddToSlot;

  const _QuickChannelsBottomSheet({required this.onAddToSlot});

  @override
  Widget build(BuildContext context) {
    final store = MultiWindowStore.instance;
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Color(0xFF080A0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white12, width: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: _QuickChannelList(
          onSelect: (ch) {
            final slot = store.nextAvailableSlot() ?? 0;
            onAddToSlot(ch, slot);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

class _QuickChannelList extends StatefulWidget {
  final ValueChanged<IptvChannel> onSelect;

  const _QuickChannelList({required this.onSelect});

  @override
  State<_QuickChannelList> createState() => _QuickChannelListState();
}

class _QuickChannelListState extends State<_QuickChannelList> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final filtered = QuickChannelList.all.where((qc) {
      return switch (_filter) {
        'US' => qc.regions.contains('US'),
        'UK' => qc.regions.contains('UK'),
        'CA' => qc.regions.contains('CA'),
        'Premium' => qc.tags.contains('premium'),
        'Sports' => qc.tags.contains('sports'),
        'News' => qc.tags.contains('news'),
        'Bay Area' => qc.regions.contains('bay-area'),
        _ => true,
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Quick Channels',
              style: TextStyle(
                color: Color(0xFFE0E0E0),
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const Spacer(),
            Text(
              '${filtered.length}',
              style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in const [
                'All',
                'Bay Area',
                'US',
                'UK',
                'CA',
                'Premium',
                'Sports',
                'News',
              ]) ...[
                _QcTabChip(
                  label: tab,
                  active: _filter == tab,
                  onTap: () => setState(() => _filter = tab),
                ),
                if (tab != 'News') const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No quick channels match filter',
                    style: TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final qc = filtered[index];
                    return _QuickChannelRow(
                      quickChannel: qc,
                      onTap: () => _resolveAndSelect(context, qc),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _resolveAndSelect(BuildContext context, QuickChannel qc) async {
    // Show a loading dialog while scanning all sources for matches.
    final result = await showDialog<List<IptvChannel>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuickResolveDialog(quickChannel: qc),
    );
    if (result == null) return;
    final channel = await _pickWorkingChannel(context, qc, result);
    if (channel != null && context.mounted) {
      widget.onSelect(channel);
    }
  }

  Future<IptvChannel?> _pickWorkingChannel(
    BuildContext context,
    QuickChannel qc,
    List<IptvChannel> matches,
  ) {
    return showDialog<IptvChannel>(
      context: context,
      builder: (_) => _QuickMatchPickerDialog(
        quickChannel: qc,
        matches: matches,
      ),
    );
  }
}

class _QcTabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _QcTabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF7C5CFF) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFB0B0B0),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _QuickChannelRow extends StatelessWidget {
  final QuickChannel quickChannel;
  final VoidCallback onTap;

  const _QuickChannelRow({required this.quickChannel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                quickChannel.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF7C5CFF),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scans all sources for channels matching [quickChannel].
class _QuickResolveDialog extends StatefulWidget {
  final QuickChannel quickChannel;

  const _QuickResolveDialog({required this.quickChannel});

  @override
  State<_QuickResolveDialog> createState() => _QuickResolveDialogState();
}

class _QuickResolveDialogState extends State<_QuickResolveDialog> {
  List<IptvChannel>? _matches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final allChannels = IptvRepository.instance.getAllChannels();
    final matches =
        allChannels.where((ch) => QuickChannelList.matches(widget.quickChannel, ch)).toList();
    if (!mounted) return;
    if (matches.isEmpty) {
      setState(() {
        _error = 'No sources found for "${widget.quickChannel.displayName}"';
      });
      return;
    }
    setState(() => _matches = matches);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      content: _error != null
          ? Text(
              _error!,
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14),
            )
          : _matches != null
              ? Text(
                  'Found ${_matches!.length} matching sources',
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF7C5CFF), strokeWidth: 2),
                    SizedBox(width: 16),
                    Text(
                      'Scanning playlists...',
                      style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                    ),
                  ],
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFFB0B0B0)),
          ),
        ),
        if (_matches != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_matches),
            child: const Text(
              'Continue',
              style: TextStyle(
                color: Color(0xFF7C5CFF),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

/// Lists working matches for a resolved quick channel with a status refresh.
class _QuickMatchPickerDialog extends StatefulWidget {
  final QuickChannel quickChannel;
  final List<IptvChannel> matches;

  const _QuickMatchPickerDialog({
    required this.quickChannel,
    required this.matches,
  });

  @override
  State<_QuickMatchPickerDialog> createState() =>
      _QuickMatchPickerDialogState();
}

class _QuickMatchPickerDialogState extends State<_QuickMatchPickerDialog> {
  String _query = '';
  Map<String, bool?> _alive = {};

  @override
  void initState() {
    super.initState();
    _checkAlive();
  }

  Future<void> _checkAlive() async {
    // Initial optimistic status from the validation store.
    final store = StreamValidationStore.instance;
    final alive = <String, bool?>{};
    for (final ch in widget.matches) {
      alive[ch.url] = switch (store.statusOf(ch.url)) {
        StreamStatus.alive => true,
        StreamStatus.dead => false,
        _ => null,
      };
    }
    if (mounted) setState(() => _alive = alive);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.matches.where((ch) {
      if (_query.isEmpty) return true;
      return ch.name.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      title: Text(
        widget.quickChannel.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFE0E0E0),
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      content: SizedBox(
        width: 360,
        height: 360,
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search channels...',
                hintStyle: const TextStyle(
                  color: Color(0x80B0B0B0),
                  fontSize: 13,
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF111111),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFFB0B0B0),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No channels match',
                        style: TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final ch = filtered[index];
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pop(ch),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111111),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE0E0E0),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (_alive[ch.url] == true)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF4CAF50),
                                    size: 14,
                                  ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Select',
                                  style: TextStyle(
                                    color: Color(0xFF7C5CFF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFFB0B0B0)),
          ),
        ),
      ],
    );
  }
}