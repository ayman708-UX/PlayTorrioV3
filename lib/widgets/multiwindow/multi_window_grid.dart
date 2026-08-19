import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/multiwindow/multi_window_models.dart';
import '../../services/iptv/multi_window_layouts.dart';
import '../../services/iptv/multi_window_player_engine.dart';
import '../../services/iptv/multi_window_store.dart';

const _primary = Color(0xFF7C5CFF);
const _cyan = Color(0xFF00F0FF);
const _gold = Color(0xFFFFD700);
const _surfaceContainer = Color(0xFF1A1A1D);
const _surfaceContainerLow = Color(0xFF151822);
const _surfaceContainerHigh = Color(0xFF25272E);
const _onSurface = Color(0xFFE5E2E1);
const _onSurfaceVariant = Color(0xFFC1C6D7);
const _outlineVariant = Color(0xFF414755);
const _errorColor = Color(0xFFFFB4AB);
const _glassBg = Color(0x991E1E1E);

/// The MultiNutz video grid (mirrors `MultiWindowGrid.kt`).
class MultiWindowGrid extends StatelessWidget {
  const MultiWindowGrid({
    super.key,
    required this.streams,
    required this.onRemoveStream,
    required this.onAddMore,
    required this.onCellLongPress,
    required this.onCellVolumeToggle,
    this.onBookmarksClick,
    this.onQuickChannelsClick,
    this.onMuteAll,
    this.onCloseAll,
    this.onPauseAll,
    this.onRefreshAll,
    this.onFullscreenCell,
  });

  final List<WindowStream> streams;
  final ValueChanged<String> onRemoveStream;
  final VoidCallback onAddMore;
  final ValueChanged<WindowStream> onCellLongPress;
  final void Function(WindowStream, bool) onCellVolumeToggle;
  final VoidCallback? onBookmarksClick;
  final VoidCallback? onQuickChannelsClick;
  final VoidCallback? onMuteAll;
  final VoidCallback? onCloseAll;
  final VoidCallback? onPauseAll;
  final VoidCallback? onRefreshAll;
  final ValueChanged<WindowStream>? onFullscreenCell;

  @override
  Widget build(BuildContext context) {
    if (streams.isEmpty) return _EmptyState(onAddMore, onBookmarksClick);

    final store = MultiWindowStore.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait = constraints.maxWidth < constraints.maxHeight;
        final isTablet = constraints.maxWidth >= 600;
        final count = streams.length;
        final layout = store.resolveLayout(count, isPortrait, isTablet);
        final slots = calculateSlots(layout, count);
        final totalRows = slots
            .map((s) => s.row + s.rowSpan)
            .fold<int>(0, _max)
            .clamp(1, 10);
        final totalCols = slots
            .map((s) => s.col + s.colSpan)
            .fold<int>(0, _max)
            .clamp(1, 10);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(activeCount: streams.length),
            _PillRow(
              streams: streams,
              isPortrait: isPortrait,
              isTablet: isTablet,
              onBookmarksClick: onBookmarksClick,
              onQuickChannelsClick: onQuickChannelsClick,
              onMuteAll: onMuteAll,
              onCloseAll: onCloseAll,
              onPauseAll: onPauseAll,
              onRefreshAll: onRefreshAll,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildGrid(
                  slots: slots,
                  totalRows: totalRows,
                  totalCols: totalCols,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrid({
    required List<SlotPos> slots,
    required int totalRows,
    required int totalCols,
  }) {
    final store = MultiWindowStore.instance;
    var gridPos = 0;
    final rows = <Widget>[];
    for (var row = 0; row < totalRows; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < totalCols; col++) {
        SlotPos? slot;
        for (final s in slots) {
          if (s.row == row && s.col == col) {
            slot = s;
            break;
          }
        }
        if (slot == null) continue;
        final stream = slot.index < streams.length ? streams[slot.index] : null;
        if (stream == null) {
          cells.add(
            Expanded(
              flex: slot.colSpan,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _surfaceContainerLow.withValues(alpha: 0.5),
                    border: Border.all(
                      color: _outlineVariant.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ),
          );
          continue;
        }
        gridPos++;
        final isAudioFocused = store.isAudioFocused(stream.id);
        cells.add(
          Expanded(
            flex: slot.colSpan,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _VideoCell(
                stream: stream,
                gridPosition: gridPos,
                isAudioFocused: isAudioFocused,
                onRemove: () => onRemoveStream(stream.id),
                onLongPress: () => onCellLongPress(stream),
                onVolumeToggle: (active) =>
                    onCellVolumeToggle(stream, active),
                onFullscreen: onFullscreenCell == null
                    ? null
                    : () => onFullscreenCell!(stream),
                onCompletion: () => onRemoveStream(stream.id),
                onSwapLeft: _swapHandler(store, stream, -1),
                onSwapRight: _swapHandler(store, stream, 1),
              ),
            ),
          ),
        );
      }
      rows.add(Row(children: cells));
    }
    return Column(children: rows.map((r) => Expanded(child: r)).toList());
  }

  VoidCallback? _swapHandler(MultiWindowStore store, WindowStream stream, int dir) {
    final occupied = streams.map((s) => s.slotIndex).toList()..sort();
    final curIdx = occupied.indexOf(stream.slotIndex);
    if (curIdx < 0) return null;
    final targetIdx = curIdx + dir;
    if (targetIdx < 0 || targetIdx >= occupied.length) return null;
    final target = occupied[targetIdx];
    return () => store.swapSlots(stream.slotIndex, target);
  }
}

int _max(int a, int b) => a > b ? a : b;

// ── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddMore;
  final VoidCallback? onBookmarksClick;

  const _EmptyState(this.onAddMore, this.onBookmarksClick);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Text(
              'MW',
              style: TextStyle(
                color: Color(0x66C1C6D7),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No streams added',
            style: TextStyle(color: _onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onAddMore,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text(
                'Browse IPTV Channels',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          if (onBookmarksClick != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onBookmarksClick,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _outlineVariant.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: const Text(
                  '★ Saved Layouts',
                  style: TextStyle(
                    color: _onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int activeCount;

  const _Header({required this.activeCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          const Text(
            'MultiNutz',
            style: TextStyle(
              color: _primary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _cyan.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _cyan,
                    boxShadow: [
                      BoxShadow(
                        color: _cyan.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$activeCount ACTIVE',
                  style: const TextStyle(
                    color: _cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pill row ──────────────────────────────────────────────────────────────

class _PillRow extends StatelessWidget {
  final List<WindowStream> streams;
  final bool isPortrait;
  final bool isTablet;
  final VoidCallback? onBookmarksClick;
  final VoidCallback? onQuickChannelsClick;
  final VoidCallback? onMuteAll;
  final VoidCallback? onCloseAll;
  final VoidCallback? onPauseAll;
  final VoidCallback? onRefreshAll;

  const _PillRow({
    required this.streams,
    required this.isPortrait,
    required this.isTablet,
    required this.onBookmarksClick,
    required this.onQuickChannelsClick,
    required this.onMuteAll,
    required this.onCloseAll,
    required this.onPauseAll,
    required this.onRefreshAll,
  });

  @override
  Widget build(BuildContext context) {
    final store = MultiWindowStore.instance;
    final count = streams.length;
    final validLayouts = getValidLayouts(count, isPortrait, isTablet);
    final isAuto = !store.layoutLocked.value;

    final pills = <Widget>[
      _Pill(
        label: 'Auto',
        active: isAuto,
        onTap: store.setAutoLayout,
      ),
      for (final l in validLayouts)
        _Pill(
          label: l.label,
          active: store.currentLayout.value == l ||
              (isAuto && defaultLayout(count, isPortrait, isTablet) == l),
          onTap: () => store.setLayout(l),
        ),
    ];

    final items = <Widget>[...pills];
    if (onBookmarksClick != null || onQuickChannelsClick != null) {
      items.add(_pillDivider);
    }
    if (onBookmarksClick != null) {
      items.add(
        _Pill(
          label: '★ Bookmarks',
          bordered: true,
          accent: _gold,
          onTap: onBookmarksClick!,
        ),
      );
    }
    if (onQuickChannelsClick != null) {
      items.add(
        _Pill(
          label: '⚡ Quick',
          bordered: true,
          accentText: true,
          onTap: onQuickChannelsClick!,
        ),
      );
    }
    if (onMuteAll != null && streams.isNotEmpty) {
      final allMuted = streams.every(
        (s) => store.getVolume(s.id) == 0,
      );
      items.add(
        _Pill(
          label: allMuted ? 'Sound All' : 'Mute All',
          active: !allMuted,
          bordered: !allMuted,
          onTap: onMuteAll!,
        ),
      );
    }
    if (onPauseAll != null && streams.isNotEmpty) {
      final allPaused = streams.every((s) => store.isPaused(s.id));
      items.add(
        _Pill(
          label: allPaused ? 'Play All' : 'Pause All',
          active: !allPaused,
          bordered: !allPaused,
          onTap: onPauseAll!,
        ),
      );
    }
    if (onRefreshAll != null && streams.isNotEmpty) {
      items.add(
        _Pill(
          label: 'Refresh All',
          bordered: true,
          onTap: onRefreshAll!,
        ),
      );
    }
    if (onCloseAll != null && streams.isNotEmpty) {
      items.add(
        _Pill(
          label: 'Close All',
          bordered: true,
          error: true,
          onTap: onCloseAll!,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(children: [
        for (final (i, pill) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          pill,
        ],
      ]),
    );
  }
}

const _pillDivider = SizedBox(
  width: 0.5,
  height: 16,
  child: ColoredBox(color: Color(0x59414755)),
);

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final bool bordered;
  final bool accentText;
  final bool error;
  final Color? accent;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    this.active = false,
    this.bordered = false,
    this.accentText = false,
    this.error = false,
    this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (active) {
      bg = _primary;
      fg = Colors.white;
    } else {
      bg = _surfaceContainer;
      fg = error
          ? _errorColor
          : accent != null
              ? accent!
              : accentText
                  ? _primary
                  : _onSurfaceVariant;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: bordered
              ? Border.all(
                  color: error
                      ? const Color(0x4DFFB4AB)
                      : _outlineVariant.withValues(alpha: 0.3),
                  width: 0.5,
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Video cell ────────────────────────────────────────────────────────────

class _VideoCell extends StatefulWidget {
  final WindowStream stream;
  final int gridPosition;
  final bool isAudioFocused;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onVolumeToggle;
  final VoidCallback? onFullscreen;
  final VoidCallback? onCompletion;
  final VoidCallback? onSwapLeft;
  final VoidCallback? onSwapRight;

  const _VideoCell({
    required this.stream,
    required this.gridPosition,
    required this.isAudioFocused,
    required this.onRemove,
    required this.onLongPress,
    required this.onVolumeToggle,
    required this.onFullscreen,
    required this.onCompletion,
    required this.onSwapLeft,
    required this.onSwapRight,
  });

  @override
  State<_VideoCell> createState() => _VideoCellState();
}

class _VideoCellState extends State<_VideoCell> {
  bool _controlsVisible = true;
  bool _isPlaying = true;
  bool _isAudioActive = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _isAudioActive = MultiWindowStore.instance.getVolume(widget.stream.id) > 0;
    final url = widget.stream.url;
    if (url != null && url.isNotEmpty) {
      _initPlayer(url);
    }
    _scheduleHide();
  }

  Future<void> _initPlayer(String url) async {
    final controller = await MultiWindowPlayerManager.instance.createPlayer(
      widget.stream.id,
      url,
      onCompletion: widget.onCompletion,
    );
    if (!mounted || controller == null) return;
    final store = MultiWindowStore.instance;
    store.storePlayerHandle(widget.stream.id, widget.stream.id);
    controller.setVolume(store.getVolume(widget.stream.id));
    if (store.isAudioFocused(widget.stream.id)) {
      MultiWindowPlayerManager.instance.setAudioFocus(widget.stream.id);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _interact() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
    MultiWindowStore.instance.setAudioFocus(widget.stream.id);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    MultiWindowPlayerManager.instance.releasePlayer(widget.stream.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = MultiWindowStore.instance;
    final resizeMode = store.getResizeMode(widget.stream.id);
    final controller =
        MultiWindowPlayerManager.instance.controllerFor(widget.stream.id);

    return GestureDetector(
      onTap: _interact,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isAudioFocused
                ? _primary
                : _outlineVariant.withValues(alpha: 0.3),
            width: widget.isAudioFocused ? 2 : 0.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MultiWindowVideoSurface(
              controller: controller,
              resizeMode: resizeMode,
            ),
            // Glass overlay controls
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: _glassBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top-left badge
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  '${widget.gridPosition} | ${widget.stream.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // Top-right fullscreen
          if (widget.onFullscreen != null)
            Positioned(
              right: 6,
              top: 6,
              child: _RoundButton(
                icon: Icons.fullscreen_rounded,
                onTap: () {
                  widget.onFullscreen!();
                  _interact();
                },
              ),
            ),
          // Left swap
          if (widget.onSwapLeft != null)
            Positioned(
              left: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RoundButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    widget.onSwapLeft!();
                    _interact();
                  },
                ),
              ),
            ),
          // Center play/pause
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() => _isPlaying = !_isPlaying);
                final manager = MultiWindowPlayerManager.instance;
                if (_isPlaying) {
                  manager.resumePlayer(widget.stream.id);
                } else {
                  manager.pausePlayer(widget.stream.id);
                }
                _interact();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _primary.withValues(alpha: 0.2),
                  border: Border.all(
                    color: _primary.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  _isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: _primary,
                  size: 18,
                ),
              ),
            ),
          ),
          // Right swap
          if (widget.onSwapRight != null)
            Positioned(
              right: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RoundButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () {
                    widget.onSwapRight!();
                    _interact();
                  },
                ),
              ),
            ),
          // Bottom-right volume
          Positioned(
            right: 6,
            bottom: 6,
            child: GestureDetector(
              onTap: () {
                final store = MultiWindowStore.instance;
                final active = !_isAudioActive;
                setState(() => _isAudioActive = active);
                final vol = active ? 1.0 : 0.0;
                MultiWindowPlayerManager.instance
                    .setVolume(widget.stream.id, vol);
                store.setVolume(widget.stream.id, vol);
                if (active) {
                  MultiWindowPlayerManager.instance
                      .setAudioFocus(widget.stream.id);
                  store.setAudioFocus(widget.stream.id);
                }
                widget.onVolumeToggle(active);
                _interact();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _surfaceContainerHigh.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _outlineVariant.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isAudioActive
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      size: 12,
                      color: _isAudioActive
                          ? _primary
                          : _onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(MultiWindowStore.instance.getVolume(widget.stream.id) * 100).toInt()}%',
                      style: TextStyle(
                        color: _isAudioActive
                            ? _onSurface
                            : _onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom-left CH + ⋮
          Positioned(
            left: 6,
            bottom: 6,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    widget.onLongPress();
                    _interact();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'CH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    widget.onLongPress();
                    _interact();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _surfaceContainerHigh.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '⋮',
                      style: TextStyle(
                        color: _onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _surfaceContainerHigh.withValues(alpha: 0.7),
        ),
        child: Icon(icon, color: _onSurface, size: 14),
      ),
    );
  }
}