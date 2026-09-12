import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../services/subtitles/subtitle_parser.dart';
import '../../services/subtitles/subtitle_sync_helper.dart';
import 'player_glass.dart';

/// Full-screen right-side floating drawer for dialogue speech following & subtitle sync.
class TextSyncOverlay extends StatefulWidget {
  final Player player;
  final List<SubCue> initialCues;
  final double baseOffsetSec;
  final VoidCallback onClose;
  final Future<void> Function(List<SubCue> syncedCues, double offsetSec) onSave;

  const TextSyncOverlay({
    super.key,
    required this.player,
    required this.initialCues,
    this.baseOffsetSec = 0.0,
    required this.onClose,
    required this.onSave,
  });

  @override
  State<TextSyncOverlay> createState() => _TextSyncOverlayState();
}

class _TextSyncOverlayState extends State<TextSyncOverlay> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<SyncPoint> _points = [];
  double _nudge = 0.0;
  List<SyncSegment> _segments = [];
  int? _rangeStart;
  int? _rangeEnd;
  bool _sectionMode = false;

  int? _selectedCueIndex;
  bool _isFollowing = true;
  bool _isProgrammaticScroll = false;
  String _searchQuery = '';
  List<int> _matchedIndices = [];
  int _currentMatchIndex = 0;

  Timer? _positionUpdateTimer;
  Timer? _searchDebounceTimer;
  double _currentPositionSec = 0.0;
  bool _isPlaying = true;
  bool _isSaving = false;

  // Approximate height per subtitle row for O(1) jump calculations
  static const double _kEstimatedItemHeight = 50.0;

  @override
  void initState() {
    super.initState();
    _nudge = widget.baseOffsetSec;
    _currentPositionSec = widget.player.state.position.inMilliseconds / 1000.0;
    _isPlaying = widget.player.state.playing;

    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final posSec = widget.player.state.position.inMilliseconds / 1000.0;
      final isPl = widget.player.state.playing;

      if ((posSec - _currentPositionSec).abs() > 0.05 || isPl != _isPlaying) {
        setState(() {
          _currentPositionSec = posSec;
          _isPlaying = isPl;
        });

        if (_isFollowing && _searchQuery.isEmpty) {
          _scrollToActiveCue();
        }
      }
    });

    _searchController.addListener(() {
      _searchDebounceTimer?.cancel();
      _searchDebounceTimer = Timer(const Duration(milliseconds: 160), () {
        if (!mounted) return;
        final raw = _searchController.text.trim();
        final q = raw.toLowerCase();
        if (q != _searchQuery) {
          setState(() {
            _searchQuery = q;
            if (q.length >= 3) {
              _isFollowing = false;
              _matchedIndices = [];
              for (int i = 0; i < widget.initialCues.length; i++) {
                if (widget.initialCues[i].text.toLowerCase().contains(q)) {
                  _matchedIndices.add(i);
                }
              }
              _currentMatchIndex = 0;
            } else {
              _matchedIndices = [];
              _currentMatchIndex = 0;
            }
          });

          if (q.length >= 3 && _matchedIndices.isNotEmpty) {
            _scrollToMatch(_currentMatchIndex);
          }
        }
      });
    });

    // Auto-scroll immediately on mount to user's current dialogue position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveCue(immediate: true);
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) _scrollToActiveCue(immediate: true);
      });
    });
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  double get _currentDelta {
    return SubtitleSyncHelper.computeDelta(_currentPositionSec, _points, _nudge);
  }

  double get _effectiveSubtitleTime {
    return _currentPositionSec - _currentDelta;
  }

  int? get _activeCueIndex {
    return SubtitleParser.findActiveCueIndex(widget.initialCues, _effectiveSubtitleTime);
  }

  int get _closestCueIndex {
    return SubtitleParser.findClosestCueIndex(widget.initialCues, _effectiveSubtitleTime);
  }

  void _scrollToIndex(int targetIndex, {bool immediate = false}) {
    if (!_scrollController.hasClients || widget.initialCues.isEmpty) return;
    if (targetIndex < 0 || targetIndex >= widget.initialCues.length) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final itemOffset = targetIndex * _kEstimatedItemHeight;
    final targetOffset = (itemOffset - (viewportHeight / 2) + (_kEstimatedItemHeight / 2)).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _isProgrammaticScroll = true;
    if (immediate) {
      _scrollController.jumpTo(targetOffset);
      _isProgrammaticScroll = false;
    } else {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ).then((_) {
        _isProgrammaticScroll = false;
      });
    }
  }

  void _scrollToActiveCue({bool immediate = false, int? targetIndex}) {
    final idx = targetIndex ?? _activeCueIndex ?? _closestCueIndex;
    _scrollToIndex(idx, immediate: immediate);
  }

  void _scrollToMatch(int matchIdx) {
    if (_matchedIndices.isEmpty || matchIdx < 0 || matchIdx >= _matchedIndices.length) return;
    final targetCueIdx = _matchedIndices[matchIdx];
    _scrollToIndex(targetCueIdx);
  }

  void _goToNextMatch() {
    if (_matchedIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchedIndices.length;
    });
    _scrollToMatch(_currentMatchIndex);
  }

  void _goToPrevMatch() {
    if (_matchedIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchedIndices.length) % _matchedIndices.length;
    });
    _scrollToMatch(_currentMatchIndex);
  }

  void _jumpToNow() {
    setState(() => _isFollowing = true);
    _scrollToActiveCue();
  }

  void _handleSyncFromHere(int cueIndex) {
    final cue = widget.initialCues[cueIndex];
    final playbackPos = _currentPositionSec;

    setState(() {
      if (_sectionMode && _rangeStart != null && _rangeEnd != null) {
        final lo = _rangeStart! < _rangeEnd! ? _rangeStart! : _rangeEnd!;
        final hi = _rangeStart! > _rangeEnd! ? _rangeStart! : _rangeEnd!;
        final curDelta = SubtitleSyncHelper.computeDelta(cue.start, _points, _nudge);
        final offset = (playbackPos - cue.start - curDelta);

        _segments = _segments.where((s) => !(s.startIdx == lo && s.endIdx == hi)).toList()
          ..add(SyncSegment(startIdx: lo, endIdx: hi, offsetSec: (offset * 1000).round() / 1000.0));

        _rangeStart = null;
        _rangeEnd = null;
        _selectedCueIndex = null;
        return;
      }

      final newPoint = SyncPoint(t: cue.start, at: playbackPos);
      if (_points.length < 2) {
        _points = [..._points, newPoint];
      } else {
        _points = [_points[0], newPoint];
      }
      _nudge = 0.0;
      _selectedCueIndex = null;
    });

    if (_isFollowing) {
      _scrollToActiveCue(targetIndex: cueIndex);
    }
  }

  void _handleSeekTo(int cueIndex) {
    final cue = widget.initialCues[cueIndex];
    final targetSec = cue.start + _currentDelta;
    final targetMs = (targetSec * 1000).round().clamp(0, widget.player.state.duration.inMilliseconds);
    widget.player.seek(Duration(milliseconds: targetMs));
  }

  void _handleNudge(double delta) {
    setState(() {
      _nudge = ((_nudge + delta) * 1000).round() / 1000.0;
    });

    if (_isFollowing) {
      _scrollToActiveCue();
    }
  }

  void _handleReset() {
    setState(() {
      _points = [];
      _nudge = 0.0;
      _segments = [];
      _rangeStart = null;
      _rangeEnd = null;
    });

    if (_isFollowing) {
      _scrollToActiveCue();
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final syncedCues = SubtitleSyncHelper.applyLinearSync(
        cues: widget.initialCues,
        points: _points,
        nudge: _nudge,
        segments: _segments,
      );

      final curDelta = SubtitleSyncHelper.computeDelta(0, _points, _nudge);
      await widget.onSave(syncedCues, curDelta);
      widget.onClose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving sync: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _isDirty =>
      _points.isNotEmpty ||
      (_nudge - widget.baseOffsetSec).abs() > 0.01 ||
      _segments.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cues = widget.initialCues;
    final activeIdx = _activeCueIndex;
    final closestIdx = _closestCueIndex;
    final currentDelta = _currentDelta;
    final screenSize = MediaQuery.sizeOf(context);
    final isLandscapeMobile = screenSize.height < 500;

    String hintText;
    if (_sectionMode) {
      hintText = 'Tap first & last line of section, then tap line playing now and "Sync from here".';
    } else if (_points.isEmpty) {
      hintText = 'Tap the line you hear right now, then tap "Sync from here".';
    } else if (_points.length == 1) {
      hintText = 'Point 1 set. If subtitles drift later on, tap "Sync from here" at a later line.';
    } else {
      hintText = 'Drift correction active (2 anchor points). Fine-tune with buttons.';
    }

    final panelWidth = isLandscapeMobile
        ? (screenSize.width * 0.58).clamp(300.0, 440.0)
        : (screenSize.width * 0.90).clamp(280.0, 480.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: panelWidth,
          height: MediaQuery.sizeOf(context).height,
          child: Container(
            decoration: const BoxDecoration(
            color: Color(0xF4080C12),
            border: Border(
              left: BorderSide(color: PlayerTheme.edge),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0xCC000000),
                blurRadius: 36,
                offset: Offset(-8, 0),
              ),
            ],
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Bar
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    isLandscapeMobile ? 8 : 16,
                    12,
                    isLandscapeMobile ? 4 : 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: PlayerTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.sync_alt_rounded,
                          color: PlayerTheme.accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _sectionMode ? 'FIX SECTION' : 'SUBTITLE TIMING',
                              style: const TextStyle(
                                color: PlayerTheme.inkSubtle,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              _sectionMode ? 'Select Range & Sync' : 'Speech Dialogue Sync',
                              style: TextStyle(
                                color: PlayerTheme.ink,
                                fontSize: isLandscapeMobile ? 14 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      PlayerIconButton(
                        size: 30,
                        iconSize: 15,
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),

                // Hint Banner (Compact on mobile)
                if (!isLandscapeMobile)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Text(
                      hintText,
                      style: const TextStyle(
                        color: PlayerTheme.inkMuted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ),

                SizedBox(height: isLandscapeMobile ? 4 : 8),

                // Search Bar with Search Navigation Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    height: isLandscapeMobile ? 32 : 36,
                    decoration: BoxDecoration(
                      color: PlayerTheme.raised,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: _searchQuery.isNotEmpty && _matchedIndices.isNotEmpty
                            ? const Color(0xFFFFC107).withValues(alpha: 0.45)
                            : PlayerTheme.edge,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: _searchQuery.isNotEmpty && _matchedIndices.isNotEmpty
                              ? const Color(0xFFFFC107)
                              : PlayerTheme.inkSubtle,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(color: PlayerTheme.ink, fontSize: isLandscapeMobile ? 12 : 12.5),
                            onSubmitted: (_) => _goToNextMatch(),
                            decoration: const InputDecoration(
                              hintText: 'Search dialogue...',
                              hintStyle: TextStyle(color: PlayerTheme.inkSubtle, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchController.text.trim().isNotEmpty) ...[
                          // Match counter
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _searchQuery.length >= 3 && _matchedIndices.isNotEmpty
                                  ? const Color(0x33FFC107)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              _searchQuery.length < 3
                                  ? '3+ chars'
                                  : (_matchedIndices.isNotEmpty
                                      ? '${_currentMatchIndex + 1}/${_matchedIndices.length}'
                                      : '0/0'),
                              style: TextStyle(
                                color: _searchQuery.length >= 3 && _matchedIndices.isNotEmpty
                                    ? const Color(0xFFFFC107)
                                    : PlayerTheme.inkSubtle,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          if (_searchQuery.length >= 3) ...[
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: _matchedIndices.isNotEmpty ? _goToPrevMatch : null,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  size: 16,
                                  color: _matchedIndices.isNotEmpty ? PlayerTheme.ink : PlayerTheme.inkSubtle,
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: _matchedIndices.isNotEmpty ? _goToNextMatch : null,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: _matchedIndices.isNotEmpty ? PlayerTheme.ink : PlayerTheme.inkSubtle,
                                ),
                              ),
                            ),
                          ],
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _searchController.clear(),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, color: PlayerTheme.inkSubtle, size: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                SizedBox(height: isLandscapeMobile ? 4 : 8),

                // Virtualized Dialogue Cues List (Lazy Rendered for 60fps)
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (!_isProgrammaticScroll && notification is ScrollUpdateNotification) {
                        if (_isFollowing) {
                          setState(() => _isFollowing = false);
                        }
                      }
                      return false;
                    },
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          itemCount: cues.length,
                          cacheExtent: 300, // Pre-cache only adjacent visible rows
                          padding: EdgeInsets.only(
                            top: 4,
                            bottom: isLandscapeMobile ? 24 : 40,
                          ),
                          itemBuilder: (context, index) {
                            final cue = cues[index];
                            final isActive = index == activeIdx || (activeIdx == null && index == closestIdx && _isFollowing);
                            final isSelected = _selectedCueIndex == index && !_sectionMode;

                            // Point anchor badges
                            int? pointNum;
                            for (int p = 0; p < _points.length; p++) {
                              if ((_points[p].t - cue.start).abs() < 0.01) {
                                pointNum = p + 1;
                                break;
                              }
                            }

                            // Section range check
                            final lo = _rangeStart != null && _rangeEnd != null
                                ? (_rangeStart! < _rangeEnd! ? _rangeStart! : _rangeEnd!)
                                : null;
                            final hi = _rangeStart != null && _rangeEnd != null
                                ? (_rangeStart! > _rangeEnd! ? _rangeStart! : _rangeEnd!)
                                : null;
                            final inRange = lo != null && hi != null && index >= lo && index <= hi;
                            final inSegment = _segments.any((s) => s.contains(index));

                            final isMatch = _searchQuery.length >= 3 &&
                                cue.text.toLowerCase().contains(_searchQuery);
                            final isCurrentFocusedMatch = _searchQuery.length >= 3 &&
                                _matchedIndices.isNotEmpty &&
                                _currentMatchIndex < _matchedIndices.length &&
                                _matchedIndices[_currentMatchIndex] == index;

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                                  color: isCurrentFocusedMatch
                                      ? const Color(0x59FFC107)
                                      : isMatch
                                          ? const Color(0x26FFC107)
                                          : isActive
                                              ? PlayerTheme.accent.withValues(alpha: 0.18)
                                              : inRange
                                                  ? PlayerTheme.accent.withValues(alpha: 0.1)
                                                  : Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      if (_sectionMode) {
                                        setState(() {
                                          if (_rangeStart == null || _rangeEnd != null) {
                                            _rangeStart = index;
                                            _rangeEnd = null;
                                          } else {
                                            _rangeEnd = index;
                                          }
                                        });
                                      } else {
                                        setState(() {
                                          _selectedCueIndex = isSelected ? null : index;
                                        });
                                      }
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: isLandscapeMobile ? 6 : 8,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.04),
                                          ),
                                          left: isCurrentFocusedMatch
                                              ? const BorderSide(
                                                  color: Color(0xFFFFC107),
                                                  width: 3,
                                                )
                                              : isActive
                                                  ? const BorderSide(
                                                      color: PlayerTheme.accent,
                                                      width: 3,
                                                    )
                                                  : BorderSide.none,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Time label
                                          SizedBox(
                                            width: 44,
                                            child: Text(
                                              SubtitleParser.formatDisplayTime(cue.start),
                                              style: TextStyle(
                                                color: isActive ? PlayerTheme.accent : PlayerTheme.inkSubtle,
                                                fontSize: isLandscapeMobile ? 10.5 : 11,
                                                fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),

                                          // Dialogue text
                                          Expanded(
                                            child: _buildHighlightedText(
                                              cue.text,
                                              _searchQuery,
                                              isActive,
                                              fontSize: isLandscapeMobile ? 12 : 12.5,
                                            ),
                                          ),

                                          const SizedBox(width: 6),

                                          // Right badge
                                          if (pointNum != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: PlayerTheme.accent,
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'P$pointNum',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          else if (isActive)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: PlayerTheme.accent,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'NOW',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            )
                                          else if (inSegment)
                                            const Icon(
                                              Icons.check_rounded,
                                              color: PlayerTheme.accent,
                                              size: 15,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Expanded Action Box for Selected Line
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    color: PlayerTheme.raised,
                                    child: Row(
                                      children: [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: PlayerTheme.accent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                          ),
                                          icon: const Icon(Icons.check_rounded, size: 14),
                                          label: const Text(
                                            'Sync from here',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                          onPressed: () => _handleSyncFromHere(index),
                                        ),
                                        const SizedBox(width: 6),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: PlayerTheme.inkMuted,
                                            side: const BorderSide(color: PlayerTheme.edgeSoft),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                          ),
                                          icon: const Icon(Icons.play_arrow_rounded, size: 14),
                                          label: const Text('Jump here', style: TextStyle(fontSize: 11)),
                                          onPressed: () => _handleSeekTo(index),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                        // Floating Jump to now button
                        if (!_isFollowing && _searchQuery.isEmpty)
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: PlayerTheme.accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  shadowColor: Colors.black,
                                  elevation: 6,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                icon: const Icon(Icons.arrow_downward_rounded, size: 13),
                                label: const Text(
                                  'Jump to now',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                onPressed: _jumpToNow,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Compact Bottom Control Dock
                _buildBottomControlDock(isLandscapeMobile, currentDelta),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildBottomControlDock(bool isLandscapeMobile, double currentDelta) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E16),
        border: Border(top: BorderSide(color: PlayerTheme.edgeSoft)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        isLandscapeMobile ? 6 : 8,
        12,
        isLandscapeMobile ? 6 : 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nudge and section row
          Row(
            children: [
              _NudgeButton(label: '−0.1s', onTap: () => _handleNudge(-0.1)),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: PlayerTheme.raised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PlayerTheme.edge),
                ),
                child: Text(
                  '${currentDelta >= 0 ? '+' : ''}${currentDelta.toStringAsFixed(2)}s',
                  style: const TextStyle(
                    color: PlayerTheme.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _NudgeButton(label: '+0.1s', onTap: () => _handleNudge(0.1)),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: _sectionMode ? PlayerTheme.accent : PlayerTheme.inkMuted,
                  backgroundColor: _sectionMode
                      ? PlayerTheme.accent.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.content_cut_rounded, size: 12),
                label: Text(_sectionMode ? 'Selecting' : 'Fix section', style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  setState(() {
                    _sectionMode = !_sectionMode;
                    _rangeStart = null;
                    _rangeEnd = null;
                  });
                },
              ),
              if (_isDirty) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.replay_rounded, size: 15, color: PlayerTheme.inkSubtle),
                  tooltip: 'Reset timing',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _handleReset,
                ),
              ],
            ],
          ),

          SizedBox(height: isLandscapeMobile ? 4 : 8),

          // Play/Pause and Save Timing row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: PlayerTheme.edgeSoft),
                    padding: EdgeInsets.symmetric(vertical: isLandscapeMobile ? 6 : 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 15,
                  ),
                  label: Text(
                    _isPlaying ? 'Pause' : 'Play',
                    style: TextStyle(fontSize: isLandscapeMobile ? 11 : 12),
                  ),
                  onPressed: () {
                    setState(() {
                      if (_isPlaying) {
                        widget.player.pause();
                        _isPlaying = false;
                      } else {
                        widget.player.play();
                        _isPlaying = true;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PlayerTheme.accent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: isLandscapeMobile ? 6 : 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.8),
                        )
                      : const Icon(Icons.check_rounded, size: 15),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save Timing',
                    style: TextStyle(
                      fontSize: isLandscapeMobile ? 11 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isSaving ? null : _handleSave,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(
    String text,
    String query,
    bool isActive, {
    double fontSize = 12.5,
  }) {
    if (query.isEmpty || query.length < 3) {
      return Text(
        text,
        style: TextStyle(
          color: isActive ? PlayerTheme.ink : PlayerTheme.inkMuted,
          fontSize: fontSize,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          height: 1.3,
        ),
      );
    }

    final lowerText = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(query, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFC107),
            color: Color(0xFF000000),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: isActive ? PlayerTheme.ink : PlayerTheme.inkMuted,
          fontSize: fontSize,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          height: 1.3,
        ),
        children: spans,
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NudgeButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              color: PlayerTheme.inkMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
