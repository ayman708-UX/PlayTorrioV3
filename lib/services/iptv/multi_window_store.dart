// Port of `MultiWindowStore.kt` from `features/hub`.
import 'package:flutter/foundation.dart';

import '../../models/iptv/iptv_models.dart';
import '../../models/multiwindow/multi_window_models.dart';
import 'multi_window_layouts.dart';

/// Reactive singleton that owns the state of the MultiNutz grid.
///
/// Mirrors `MultiWindowStore.kt`: streams live in a `ValueNotifier` (the Dart
/// analogue of Compose's `mutableStateListOf`), while volumes / pause /
/// resize-modes / audio-focus are side maps keyed by stream id.
class MultiWindowStore {
  MultiWindowStore._();

  static final MultiWindowStore instance = MultiWindowStore._();

  static const int maxSlots = 9;

  final ValueNotifier<List<WindowStream>> streams = ValueNotifier(const []);
  final ValueNotifier<MultiWindowLayout?> currentLayout =
      ValueNotifier<MultiWindowLayout?>(null);
  final ValueNotifier<bool> layoutLocked = ValueNotifier(false);

  final Map<String, double> _volumes = {};
  final Map<String, bool> _paused = {};
  final Map<String, int> _resizeModes = {};
  final Map<String, String> _playerHandleIds = {};
  String? _audioFocusId;
  int _idCounter = 0;

  String get audioFocusId => _audioFocusId ?? '';

  /// Builds a stream id. [channel] is the backing IPTV channel for grid cells;
  /// [url]/[title]/[poster] describe a generic (non-IPTV) stream.
  String _makeId() => 'mw_${++_idCounter}';

  void _replaceAtSlot(
    int slotIndex,
    WindowStream Function(String id) makeStream,
  ) {
    final current = List.of(streams.value);
    final existingAtSlot = current.indexWhere((s) => s.slotIndex == slotIndex);
    if (existingAtSlot >= 0) {
      final oldId = current[existingAtSlot].id;
      current[existingAtSlot] = makeStream(oldId);
      _removeSideState(oldId);
    } else {
      current.add(makeStream(_makeId()));
    }
    streams.value = current;
    if (currentLayout.value == null) layoutLocked.value = false;
  }

  void _removeSideState(String id) {
    _volumes.remove(id);
    _paused.remove(id);
    _resizeModes.remove(id);
    _playerHandleIds.remove(id);
    if (_audioFocusId == id) _audioFocusId = null;
  }

  bool _grantAudioFocus(String id) {
    final hasFocus = _audioFocusId == null;
    if (hasFocus) _audioFocusId = id;
    _volumes[id] = hasFocus ? 1.0 : 0.0;
    return hasFocus;
  }

  /// Adds an IPTV channel into [slotIndex], replacing any existing stream.
  void addToSlot(IptvChannel channel, int slotIndex) {
    _replaceAtSlot(slotIndex, (id) {
      _grantAudioFocus(id);
      return WindowStream(
        id: id,
        title: channel.name,
        url: channel.url,
        poster: channel.logo,
        channel: channel,
        slotIndex: slotIndex,
      );
    });
  }

  /// Adds a generic stream (movie/show/sports URL) into [slotIndex].
  void addStream({
    required String url,
    required String title,
    String? poster,
    required int slotIndex,
  }) {
    _replaceAtSlot(slotIndex, (id) {
      _grantAudioFocus(id);
      return WindowStream(
        id: id,
        title: title,
        url: url,
        poster: poster,
        slotIndex: slotIndex,
      );
    });
  }

  void removeSlot(int slotIndex) {
    final current = List.of(streams.value);
    final removed = current.where((s) => s.slotIndex == slotIndex).toList();
    for (final s in removed) {
      _removeSideState(s.id);
    }
    current.removeWhere((s) => s.slotIndex == slotIndex);
    streams.value = current;
  }

  void remove(String id) {
    _removeSideState(id);
    streams.value = List.of(streams.value)..removeWhere((s) => s.id == id);
  }

  WindowStream? streamForSlot(int slotIndex) {
    for (final s in streams.value) {
      if (s.slotIndex == slotIndex) return s;
    }
    return null;
  }

  List<int> get occupiedSlots =>
      streams.value.map((s) => s.slotIndex).toList();

  bool isSlotAvailable(int slotIndex) => streamForSlot(slotIndex) == null;

  int? nextAvailableSlot() {
    for (var i = 0; i < maxSlots; i++) {
      if (isSlotAvailable(i)) return i;
    }
    return null;
  }

  // ── Volume / pause / audio focus ────────────────────────────────────────
  double getVolume(String streamId) => _volumes[streamId] ?? 0.0;
  void setVolume(String streamId, double volume) =>
      _volumes[streamId] = volume.clamp(0.0, 1.0);
  bool isPaused(String streamId) => _paused[streamId] ?? false;
  void setPaused(String streamId, bool value) => _paused[streamId] = value;
  void setAudioFocus(String streamId) => _audioFocusId = streamId;
  bool isAudioFocused(String streamId) => _audioFocusId == streamId;

  // ── Player handles (mapped to `VideoPlayerController`s in the engine) ────
  void storePlayerHandle(String streamId, String handleId) =>
      _playerHandleIds[streamId] = handleId;
  String? playerHandleId(String streamId) => _playerHandleIds[streamId];

  // ── Resize mode ─────────────────────────────────────────────────────────
  void setResizeMode(String streamId, int mode) => _resizeModes[streamId] = mode;
  int getResizeMode(String streamId) => _resizeModes[streamId] ?? resizeFit;

  // ── Layout ──────────────────────────────────────────────────────────────
  void setLayout(MultiWindowLayout layout) {
    currentLayout.value = layout;
    layoutLocked.value = true;
  }

  void setAutoLayout() {
    currentLayout.value = null;
    layoutLocked.value = false;
  }

  MultiWindowLayout resolveLayout(
    int count,
    bool isPortrait,
    bool isTablet,
  ) {
    return currentLayout.value ??
        defaultLayout(count, isPortrait, isTablet);
  }

  // ── Slot operations ─────────────────────────────────────────────────────
  void swapSlots(int slotA, int slotB) {
    final current = List.of(streams.value);
    final idxA = current.indexWhere((s) => s.slotIndex == slotA);
    final idxB = current.indexWhere((s) => s.slotIndex == slotB);
    if (idxA < 0 || idxB < 0) return;
    final a = current[idxA];
    final b = current[idxB];
    current[idxA] = b.copyWith(slotIndex: slotA);
    current[idxB] = a.copyWith(slotIndex: slotB);
    streams.value = current;
  }

  void clear() {
    _volumes.clear();
    _paused.clear();
    _resizeModes.clear();
    _playerHandleIds.clear();
    _audioFocusId = null;
    streams.value = const [];
    currentLayout.value = null;
    layoutLocked.value = false;
  }

  bool get isEmpty => streams.value.isEmpty;
}

/// Resize-mode constants (mirrors `MultiWindowPlayerEngine.kt`).
const int resizeFill = 0;
const int resizeFit = 1;
const int resizeFixedWidth = 2;
const int resizeFixedHeight = 3;
const int resizeZoom = 4;