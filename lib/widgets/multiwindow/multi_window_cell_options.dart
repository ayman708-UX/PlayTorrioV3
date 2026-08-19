import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/iptv/iptv_models.dart';
import '../../models/multiwindow/multi_window_models.dart';
import '../../services/iptv/iptv_repository.dart';
import '../../services/iptv/multi_window_store.dart';
import '../../services/iptv/quick_channel_list.dart';
import '../../services/iptv/stream_validation_store.dart';

const _bg = Color(0xFF080A0F);
const _onSurface = Color(0xFFE0E0E0);
const _onSurfaceVariant = Color(0xFFB0B0B0);
const _surfaceCard = Color(0xFF1A1A1A);
const _surfaceLow = Color(0xFF111111);
const _accent = Color(0xFF7C5CFF);
const _red = Color(0xFFFF4444);
const _green = Color(0xFF4CAF50);

const _scaleLabels = ['Fill', 'Fit', '16:9', '4:3', 'Zoom'];
const _scaleModes = [
  resizeFill,
  resizeFit,
  resizeFixedWidth,
  resizeFixedHeight,
  resizeZoom,
];

const _volumeSteps = [
  ('Mute', 0.0),
  ('15', 0.15),
  ('30', 0.30),
  ('45', 0.45),
  ('70', 0.70),
  ('85', 0.85),
  ('Max', 1.0),
];

/// Full cell options sheet (mirrors `MultiWindowCellOptions.kt`).
class MultiWindowCellOptionsSheet extends StatefulWidget {
  const MultiWindowCellOptionsSheet({
    super.key,
    required this.stream,
    required this.volume,
    required this.onVolumeChange,
    this.onSwap,
    this.onRefresh,
    this.onFullscreen,
    required this.onClose,
  });

  final WindowStream stream;
  final double volume;
  final ValueChanged<double> onVolumeChange;
  final ValueChanged<int>? onSwap;
  final VoidCallback? onRefresh;
  final VoidCallback? onFullscreen;
  final VoidCallback onClose;

  static Future<void> show(
    BuildContext context, {
    required WindowStream stream,
    required double volume,
    required ValueChanged<double> onVolumeChange,
    ValueChanged<int>? onSwap,
    VoidCallback? onRefresh,
    VoidCallback? onFullscreen,
    required VoidCallback onClose,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => MultiWindowCellOptionsSheet(
        stream: stream,
        volume: volume,
        onVolumeChange: onVolumeChange,
        onSwap: onSwap,
        onRefresh: onRefresh,
        onFullscreen: onFullscreen,
        onClose: onClose,
      ),
    );
  }

  @override
  State<MultiWindowCellOptionsSheet> createState() =>
      _MultiWindowCellOptionsSheetState();
}

class _MultiWindowCellOptionsSheetState
    extends State<MultiWindowCellOptionsSheet> {
  String? _overlayMode;

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    final store = MultiWindowStore.instance;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white12, width: 0.6)),
        ),
        child: _buildBody(stream, store),
      ),
    );
  }

  Widget _buildBody(WindowStream stream, MultiWindowStore store) {
    switch (_overlayMode) {
      case 'swap':
        return _SwapPositionOverlay(
          currentSlotIndex: stream.slotIndex,
          onSelect: (target) {
            widget.onSwap?.call(target);
            Navigator.of(context).pop();
          },
          onBack: () => setState(() => _overlayMode = null),
        );
      case 'channels':
      case 'history':
      case 'favorites':
        return _ChannelOverlay(
          mode: _overlayMode!,
          onSelect: (ch) {
            store.addToSlot(ch, stream.slotIndex);
            Navigator.of(context).pop();
          },
          onBack: () => setState(() => _overlayMode = null),
        );
      case 'quick':
        return _QuickChannelOverlay(
          currentSlotIndex: stream.slotIndex,
          onSelect: (ch) {
            store.addToSlot(ch, stream.slotIndex);
            Navigator.of(context).pop();
          },
          onBack: () => setState(() => _overlayMode = null),
        );
      case 'sources':
        return _InfoOverlay(
          title: 'Sources for ${widget.stream.title}',
          onBack: () => setState(() => _overlayMode = null),
          children: [
            const Text(
              'Source switching is available in full-screen player via the Sources panel.',
              style: TextStyle(color: _onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tip: Tap Fullscreen, then use the Sources button in the player controls.',
              style: TextStyle(color: _accent, fontSize: 12),
            ),
          ],
        );
      case 'episodes':
        return _InfoOverlay(
          title: 'Episodes for ${widget.stream.title}',
          onBack: () => setState(() => _overlayMode = null),
          children: [
            const Text(
              'Episode selection is available in full-screen player via the Episodes panel.',
              style: TextStyle(color: _onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tip: Tap Fullscreen, then use the Episodes button in the player controls.',
              style: TextStyle(color: _accent, fontSize: 12),
            ),
          ],
        );
      default:
        return _buildMain(stream, store);
    }
  }

  Widget _buildMain(WindowStream stream, MultiWindowStore store) {
    final isGeneric = stream.url != null && stream.channel == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stream.title,
            style: const TextStyle(
              color: _onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            'Slot ${stream.slotIndex + 1}',
            style: const TextStyle(color: _onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 14),
          // ── Mode chips ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                label: 'CH',
                onTap: () => setState(() => _overlayMode = 'channels'),
              ),
              _Chip(
                label: 'History',
                onTap: () => setState(() => _overlayMode = 'history'),
              ),
              _Chip(
                label: 'Fav',
                onTap: () => setState(() => _overlayMode = 'favorites'),
              ),
              _Chip(
                label: 'Quick',
                onTap: () => setState(() => _overlayMode = 'quick'),
              ),
              if (isGeneric) ...[
                _Chip(
                  label: 'Sources',
                  onTap: () => setState(() => _overlayMode = 'sources'),
                ),
                _Chip(
                  label: 'Episodes',
                  onTap: () => setState(() => _overlayMode = 'episodes'),
                ),
              ],
              if (widget.onSwap != null)
                _Chip(
                  label: 'Swap',
                  onTap: () => setState(() => _overlayMode = 'swap'),
                ),
            ],
          ),
          _divider,
          const Text(
            'Volume',
            style: TextStyle(
              color: _onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (label, level) in _volumeSteps) ...[
                Expanded(
                  child: _VolumeChip(
                    label: label,
                    active: widget.volume == level,
                    onTap: () => widget.onVolumeChange(level),
                  ),
                ),
                if (label != 'Max') const SizedBox(width: 6),
              ],
            ],
          ),
          _divider,
          const Text(
            'Scaling',
            style: TextStyle(
              color: _onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _scaleLabels.length; i++) ...[
                  _ScalingChip(
                    label: _scaleLabels[i],
                    active: store.getResizeMode(stream.id) == _scaleModes[i],
                    onTap: () =>
                        store.setResizeMode(stream.id, _scaleModes[i]),
                  ),
                  if (i < _scaleLabels.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          _divider,
          if (widget.onRefresh != null) ...[
            _ActionRow(
              label: 'Refresh Stream',
              icon: Icons.refresh_rounded,
              color: _accent,
              onTap: widget.onRefresh!,
            ),
            const SizedBox(height: 8),
          ],
          if (widget.onFullscreen != null) ...[
            _ActionRow(
              label: 'Fullscreen',
              icon: Icons.fullscreen_rounded,
              color: _accent,
              onTap: widget.onFullscreen!,
            ),
            const SizedBox(height: 8),
          ],
          _ActionRow(
            label: 'Close Channel',
            icon: Icons.close_rounded,
            color: _red,
            onTap: widget.onClose,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

const _divider = SizedBox(height: 14);

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _onSurface,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _VolumeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _VolumeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? _accent : _surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ScalingChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ScalingChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _accent : _surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Icon(icon, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Swap overlay ──────────────────────────────────────────────────────────

class _SwapPositionOverlay extends StatelessWidget {
  final int currentSlotIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack;

  const _SwapPositionOverlay({
    required this.currentSlotIndex,
    required this.onSelect,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final store = MultiWindowStore.instance;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BackButton(onTap: onBack),
                const SizedBox(width: 12),
                const Text(
                  'Swap Slot',
                  style: TextStyle(
                    color: _onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Select target slot to swap with:',
              style: TextStyle(color: _onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var slot = 0; slot < MultiWindowStore.maxSlots; slot++) ...[
                  if (slot > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _SwapSlot(
                      slot: slot,
                      current: slot == currentSlotIndex,
                      occupied: store.streamForSlot(slot) != null,
                      onTap: () => onSelect(slot),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapSlot extends StatelessWidget {
  final int slot;
  final bool current;
  final bool occupied;
  final VoidCallback onTap;

  const _SwapSlot({
    required this.slot,
    required this.current,
    required this.occupied,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (current) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          '${slot + 1}',
          style: TextStyle(
            color: _onSurfaceVariant.withValues(alpha: 0.4),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: occupied ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: occupied ? _accent : _surfaceLow,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          '${slot + 1}',
          style: TextStyle(
            color: occupied ? Colors.white : _onSurfaceVariant.withValues(alpha: 0.4),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Channel overlay (all / history / favorites) ───────────────────────────

class _ChannelOverlay extends StatefulWidget {
  final String mode;
  final ValueChanged<IptvChannel> onSelect;
  final VoidCallback onBack;

  const _ChannelOverlay({
    required this.mode,
    required this.onSelect,
    required this.onBack,
  });

  @override
  State<_ChannelOverlay> createState() => _ChannelOverlayState();
}

class _ChannelOverlayState extends State<_ChannelOverlay> {
  String _searchQuery = '';
  int _selectedSource = -1;
  String _selectedGroup = '';

  @override
  Widget build(BuildContext context) {
    final repository = IptvRepository.instance;
    final allChannels = repository.getAllChannels();
    final sourceNames = repository.getAllSourceNames();
    final sourceIds = repository.getAllSourceIds();

    final channels = switch (widget.mode) {
      'history' => repository.getHistoryChannels(),
      'favorites' => repository.getFavoriteChannels(),
      _ => allChannels,
    };

    final groups = channels
        .map((c) => c.group ?? 'Other')
        .toSet()
        .toList()
      ..sort();

    final filtered = channels.where((ch) {
      if (_selectedSource >= 0 &&
          _selectedSource < sourceIds.length &&
          ch.sourceId != sourceIds[_selectedSource]) {
        return false;
      }
      if (_selectedGroup.isNotEmpty && ch.group != _selectedGroup) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !ch.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    final title = switch (widget.mode) {
      'history' => 'History',
      'favorites' => 'Favorites',
      _ => 'All Channels',
    };

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BackButton(onTap: widget.onBack),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: _onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length}',
                    style: const TextStyle(color: _onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.mode == 'channels') ...[
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: _onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search channels...',
                    hintStyle: TextStyle(
                      color: _onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: _surfaceCard,
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: _onSurfaceVariant,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        active: _selectedSource < 0,
                        onTap: () => setState(() => _selectedSource = -1),
                      ),
                      for (var i = 0; i < sourceIds.length; i++) ...[
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: sourceNames[i].length > 12
                              ? sourceNames[i].substring(0, 12)
                              : sourceNames[i],
                          active: _selectedSource == i,
                          onTap: () => setState(() => _selectedSource = i),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All Groups',
                        active: _selectedGroup.isEmpty,
                        onTap: () => setState(() => _selectedGroup = ''),
                      ),
                      for (final g in groups.take(20)) ...[
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: g.length > 16 ? g.substring(0, 16) : g,
                          active: _selectedGroup == g,
                          onTap: () => setState(() => _selectedGroup = g),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No ${widget.mode} channels match',
                          style: const TextStyle(
                            color: _onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final ch = filtered[index];
                          return _ChannelRow(
                            channel: ch,
                            trailing: _accent,
                            trailingText: '',
                            onTap: () => widget.onSelect(ch),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
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
          color: active ? _accent : _surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Quick channel overlay ─────────────────────────────────────────────────

const _qcTabs = ['All', 'Bay Area', 'US', 'UK', 'CA', 'Premium', 'Sports', 'News'];

class _QuickChannelOverlay extends StatefulWidget {
  final int currentSlotIndex;
  final ValueChanged<IptvChannel> onSelect;
  final VoidCallback onBack;

  const _QuickChannelOverlay({
    required this.currentSlotIndex,
    required this.onSelect,
    required this.onBack,
  });

  @override
  State<_QuickChannelOverlay> createState() => _QuickChannelOverlayState();
}

class _QuickChannelOverlayState extends State<_QuickChannelOverlay> {
  String _qcFilter = 'All';
  QuickChannel? _selectedQc;
  bool _loading = false;
  String? _error;
  List<IptvChannel>? _matches;
  Map<String, bool?> _aliveByUrl = {};
  String _searchQuery = '';
  int _selectedSource = -1;
  String _selectedGroup = '';

  final Map<String, _QcCache> _cache = {};

  void _loadMatches(QuickChannel qc) {
    final cached = _cache[qc.displayName];
    if (cached != null) {
      setState(() {
        _matches = cached.channels;
        _aliveByUrl = cached.alive;
      });
      return;
    }
    setState(() {
      _selectedQc = qc;
      _loading = true;
      _error = null;
      _matches = null;
      _aliveByUrl = {};
    });
    _resolveMatches(qc);
  }

  Future<void> _resolveMatches(QuickChannel qc) async {
    final repository = IptvRepository.instance;
    final allChannels = repository.getAllChannels();
    try {
      final matches = allChannels
          .where((ch) => QuickChannelList.matches(qc, ch))
          .toList();
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No sources found for "${qc.displayName}"';
        });
        return;
      }
      final statuses =
          await StreamValidationController.resolveChannelsStatuses(matches);
      if (!mounted) return;
      final alive = <String, bool?>{};
      for (final ch in matches) {
        alive[ch.url] = switch (statuses[ch.url]) {
          StreamStatus.alive => true,
          StreamStatus.dead => false,
          _ => null,
        };
      }
      _cache[qc.displayName] = _QcCache(matches, alive);
      setState(() {
        _loading = false;
        _matches = matches;
        _aliveByUrl = alive;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _retry() {
    final qc = _selectedQc;
    if (qc == null) return;
    _cache.remove(qc.displayName);
    _loadMatches(qc);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BackButton(
                    onTap: _selectedQc == null || _loading
                        ? widget.onBack
                        : () => setState(() => _selectedQc = null),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _selectedQc?.displayName ?? 'Quick Channels',
                    style: const TextStyle(
                      color: _onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const Spacer(),
                  if (_matches != null)
                    Text(
                      '${_matches!.length}',
                      style: const TextStyle(
                        color: _onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_selectedQc == null) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tab in _qcTabs) ...[
                        _FilterChip(
                          label: tab,
                          active: _qcFilter == tab,
                          onTap: () => setState(() => _qcFilter = tab),
                        ),
                        if (tab != _qcTabs.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _accent, strokeWidth: 2),
            SizedBox(height: 12),
            Text(
              'Resolving sources...',
              style: TextStyle(color: _onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      );
    }
    if (_error != null && _matches == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: _red, size: 36),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _onSurface, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _Chip(label: 'Retry', onTap: _retry),
          ],
        ),
      );
    }
    if (_selectedQc != null && _matches != null) {
      return _buildMatchesList();
    }
    return _buildQuickList();
  }

  Widget _buildQuickList() {
    final filtered = QuickChannelList.all.where((qc) {
      return switch (_qcFilter) {
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

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No quick channels match filter',
          style: TextStyle(color: _onSurfaceVariant, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final qc = filtered[index];
        return GestureDetector(
          onTap: () => _loadMatches(qc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _surfaceLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    qc.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _onSurface, fontSize: 14),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: _accent, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMatchesList() {
    final qc = _selectedQc!;
    final matches = _matches!;
    final repository = IptvRepository.instance;
    final sourceNames = repository.getAllSourceNames();
    final sourceIds = repository.getAllSourceIds();

    final groups = matches
        .map((c) => c.group ?? 'Other')
        .toSet()
        .toList()
      ..sort();

    final liveChannels =
        matches.where((ch) => _aliveByUrl[ch.url] != false).toList();

    final filtered = liveChannels.where((ch) {
      if (_selectedSource >= 0 &&
          _selectedSource < sourceIds.length &&
          ch.sourceId != sourceIds[_selectedSource]) {
        return false;
      }
      if (_selectedGroup.isNotEmpty && ch.group != _selectedGroup) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !ch.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    final checkingCount = matches
        .where((ch) => _aliveByUrl[ch.url] == null)
        .length;
    final workingCount =
        matches.where((ch) => _aliveByUrl[ch.url] == true).length;

    final sourceNameForId = <String, String>{};
    for (var i = 0; i < sourceIds.length && i < sourceNames.length; i++) {
      sourceNameForId[sourceIds[i]] = sourceNames[i];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(color: _onSurface, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search channels...',
            hintStyle: TextStyle(
              color: _onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 13,
            ),
            isDense: true,
            filled: true,
            fillColor: _surfaceCard,
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: _onSurfaceVariant),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (sourceIds.length > 1) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  active: _selectedSource < 0,
                  onTap: () => setState(() => _selectedSource = -1),
                ),
                for (var i = 0; i < sourceIds.length; i++) ...[
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: sourceNames[i].length > 12
                        ? sourceNames[i].substring(0, 12)
                        : sourceNames[i],
                    active: _selectedSource == i,
                    onTap: () => setState(() => _selectedSource = i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All Groups',
                  active: _selectedGroup.isEmpty,
                  onTap: () => setState(() => _selectedGroup = ''),
                ),
                for (final g in groups.take(20)) ...[
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: g.length > 16 ? g.substring(0, 16) : g,
                    active: _selectedGroup == g,
                    onTap: () => setState(() => _selectedGroup = g),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    checkingCount > 0
                        ? 'Checking ${qc.displayName} streams...'
                        : 'No channels match "${qc.displayName}"',
                    style: const TextStyle(
                      color: _onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final ch = filtered[index];
                    final provider =
                        sourceNameForId[ch.sourceId] ?? 'Unknown';
                    final alive = _aliveByUrl[ch.url];
                    return GestureDetector(
                      onTap: () => widget.onSelect(ch),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            if (ch.logo != null && ch.logo!.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: CachedNetworkImage(
                                  imageUrl: ch.logo!,
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    provider,
                                    style: const TextStyle(
                                      color: _accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (alive == true)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.check_circle_rounded,
                                    color: _green, size: 14),
                              )
                            else if (alive == null)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    color: _accent,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            Text(
                              'Slot ${widget.currentSlotIndex + 1}',
                              style: const TextStyle(
                                color: _accent,
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
        const SizedBox(height: 4),
        Row(
          children: [
            if (checkingCount > 0)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2,
                ),
              ),
            const SizedBox(width: 6),
            Text(
              checkingCount > 0
                  ? '$workingCount working · checking $checkingCount'
                  : '$workingCount working',
              style: const TextStyle(color: _onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _QcCache {
  final List<IptvChannel> channels;
  final Map<String, bool?> alive;

  _QcCache(this.channels, this.alive);
}

// ── Shared bits ───────────────────────────────────────────────────────────

/// Standalone "browse all IPTV channels" picker (used from the empty-state /
/// Add More action). Reuses the same channel overlay as the cell options.
class MultiWindowChannelPickerSheet {
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<IptvChannel> onSelect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => _ChannelOverlay(
        mode: 'channels',
        onSelect: (ch) {
          onSelect(ch);
          Navigator.of(sheetContext).pop();
        },
        onBack: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _surfaceCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '← Back',
          style: TextStyle(
            color: _onSurface,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _InfoOverlay extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final List<Widget> children;

  const _InfoOverlay({
    required this.title,
    required this.onBack,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BackButton(onTap: onBack),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final IptvChannel channel;
  final Color trailing;
  final String trailingText;
  final VoidCallback onTap;

  const _ChannelRow({
    required this.channel,
    required this.trailing,
    required this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (channel.logo != null && channel.logo!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: channel.logo!,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _onSurface, fontSize: 14),
              ),
            ),
            if (trailingText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                trailingText,
                style: TextStyle(color: trailing, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}