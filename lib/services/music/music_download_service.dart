import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/music/downloaded_music_track.dart';
import '../../models/music/music_track.dart';
import 'music_player_controller.dart';
import 'music_service.dart';
import 'qobuz_music_service.dart';
import 'youtube_stream_http.dart';
import 'youtube_stream_resolver.dart';

enum MusicDownloadStatus {
  queued,
  extracting,
  downloading,
  completed,
  failed,
  cancelled,
}

class MusicDownloadTask {
  final String id;
  final MusicTrack track;
  final String? collectionName;
  MusicDownloadStatus status;
  double progress; // 0.0 to 1.0
  String? format;
  String? quality;
  String? errorMessage;
  int bytesDownloaded;
  int totalBytes;

  MusicDownloadTask({
    required this.id,
    required this.track,
    this.collectionName,
    this.status = MusicDownloadStatus.queued,
    this.progress = 0.0,
    this.format,
    this.quality,
    this.errorMessage,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
  });
}

class MusicDownloadService extends ChangeNotifier {
  static final MusicDownloadService instance = MusicDownloadService._internal();
  MusicDownloadService._internal();

  static const String _storageKey = 'music_downloaded_tracks_v3';

  final List<DownloadedMusicTrack> _downloadedTracks = [];
  final List<MusicDownloadTask> _queue = [];
  bool _isProcessing = false;
  bool _initialized = false;

  Directory? _musicDir;
  Directory? _tracksDir;
  Directory? _coversDir;

  List<DownloadedMusicTrack> get downloadedTracks => List.unmodifiable(_downloadedTracks);
  List<MusicDownloadTask> get queue => List.unmodifiable(_queue);
  bool get isProcessing => _isProcessing;

  int get totalDownloadedSizeBytes =>
      _downloadedTracks.fold<int>(0, (sum, t) => sum + t.fileSizeBytes);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _musicDir = Directory(p.join(appDocDir.path, 'PlayTorrio', 'Music'));
      _tracksDir = Directory(p.join(_musicDir!.path, 'Tracks'));
      _coversDir = Directory(p.join(_musicDir!.path, 'Covers'));

      if (!await _tracksDir!.exists()) await _tracksDir!.create(recursive: true);
      if (!await _coversDir!.exists()) await _coversDir!.create(recursive: true);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _downloadedTracks.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final track = DownloadedMusicTrack.fromJson(item);
            // Verify file exists on disk
            final f = File(track.localAudioPath);
            if (f.existsSync() && f.lengthSync() > 100) {
              _downloadedTracks.add(track);
            }
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[MusicDownloadService] init error: $e');
    }
  }

  bool isDownloaded(String trackId) {
    return _downloadedTracks.any((t) => t.id == trackId);
  }

  DownloadedMusicTrack? getDownloadedTrack(String trackId) {
    try {
      return _downloadedTracks.firstWhere((t) => t.id == trackId);
    } catch (_) {
      return null;
    }
  }

  File? getDownloadedTrackFile(String trackId) {
    final track = getDownloadedTrack(trackId);
    if (track == null) return null;
    final f = File(track.localAudioPath);
    return f.existsSync() ? f : null;
  }

  File? getDownloadedCoverFile(String trackId) {
    final track = getDownloadedTrack(trackId);
    if (track == null || track.localCoverPath.isEmpty) return null;
    final f = File(track.localCoverPath);
    return f.existsSync() ? f : null;
  }

  bool isQueued(String trackId) {
    return _queue.any((task) =>
        task.track.id == trackId &&
        (task.status == MusicDownloadStatus.queued ||
            task.status == MusicDownloadStatus.extracting ||
            task.status == MusicDownloadStatus.downloading));
  }

  MusicDownloadTask? getTask(String trackId) {
    try {
      return _queue.firstWhere((t) => t.track.id == trackId);
    } catch (_) {
      return null;
    }
  }

  /// Queues a single track for sequential download
  void queueTrack(MusicTrack track, {String? collectionName}) {
    if (isDownloaded(track.id)) return;
    if (isQueued(track.id)) return;

    final task = MusicDownloadTask(
      id: '${track.id}_${DateTime.now().millisecondsSinceEpoch}',
      track: track,
      collectionName: collectionName,
      status: MusicDownloadStatus.queued,
    );

    _queue.add(task);
    notifyListeners();
    _processQueue();
  }

  /// Queues a batch of tracks (e.g. from an album or playlist) for sequential download
  void queueTracks(List<MusicTrack> tracks, {String? collectionName}) {
    bool added = false;
    for (final track in tracks) {
      if (isDownloaded(track.id) || isQueued(track.id)) continue;
      _queue.add(MusicDownloadTask(
        id: '${track.id}_${DateTime.now().millisecondsSinceEpoch}',
        track: track,
        collectionName: collectionName,
        status: MusicDownloadStatus.queued,
      ));
      added = true;
    }

    if (added) {
      notifyListeners();
      _processQueue();
    }
  }

  /// Cancels a queued or active download task
  void cancelTask(String trackId) {
    final task = getTask(trackId);
    if (task != null) {
      task.status = MusicDownloadStatus.cancelled;
      _queue.removeWhere((t) => t.track.id == trackId);
      notifyListeners();
    }
  }

  /// Deletes a downloaded track from disk and metadata
  Future<void> deleteDownloadedTrack(String trackId) async {
    final track = getDownloadedTrack(trackId);
    if (track != null) {
      try {
        final audioFile = File(track.localAudioPath);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
        if (track.localCoverPath.isNotEmpty) {
          final coverFile = File(track.localCoverPath);
          if (await coverFile.exists()) {
            await coverFile.delete();
          }
        }
      } catch (e) {
        debugPrint('[MusicDownloadService] delete error: $e');
      }

      _downloadedTracks.removeWhere((t) => t.id == trackId);
      await _saveDownloadedTracks();
      notifyListeners();
    }
  }

  /// Clears completed or failed tasks from the active queue
  void clearCompletedTasks() {
    _queue.removeWhere((t) =>
        t.status == MusicDownloadStatus.completed ||
        t.status == MusicDownloadStatus.failed ||
        t.status == MusicDownloadStatus.cancelled);
    notifyListeners();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Sequential Queue Processing Engine
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      await init();

      while (true) {
        // Find next queued task
        MusicDownloadTask? nextTask;
        for (final task in _queue) {
          if (task.status == MusicDownloadStatus.queued) {
            nextTask = task;
            break;
          }
        }

        if (nextTask == null) break;

        await _executeDownloadTask(nextTask);
      }
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> _executeDownloadTask(MusicDownloadTask task) async {
    final track = task.track;
    task.status = MusicDownloadStatus.extracting;
    task.progress = 0.05;
    notifyListeners();

    final preferredSource = MusicPlayerController.instance.audioSource;
    String? streamUrl;
    Map<String, String> headers = {};
    String format = 'm4a';
    String quality = 'HQ Audio';

    // 1. Audio Stream Extraction with FLAC -> YouTube fallback
    try {
      if (preferredSource == MusicAudioSource.flac) {
        try {
          final flac = await QobuzMusicService.instance.resolveLosslessUrl(track);
          if (flac != null && flac.url.isNotEmpty) {
            streamUrl = flac.url;
            format = flac.format;
            quality = flac.quality;
            if (flac.headers['User-Agent'] != null) {
              headers['User-Agent'] = flac.headers['User-Agent']!;
            }
          }
        } catch (e) {
          debugPrint('[MusicDownloadService] Qobuz FLAC failed for ${track.title}, falling back to YouTube: $e');
        }
      }

      // YouTube fallback or primary
      if (streamUrl == null || streamUrl.isEmpty) {
        final yt = await YoutubeStreamResolver.instance.resolveUrl(track);
        if (yt != null && yt.url.isNotEmpty) {
          streamUrl = yt.url;
          format = 'm4a';
          quality = 'YouTube HQ';
          headers = YoutubeStreamHttp.streamHeaders(
            yt.url,
            userAgent: yt.userAgent,
          );
        }
      }
    } catch (e) {
      debugPrint('[MusicDownloadService] Stream resolution failed for ${track.title}: $e');
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      task.status = MusicDownloadStatus.failed;
      task.errorMessage = 'Could not find a valid audio stream.';
      notifyListeners();
      return;
    }

    task.format = format;
    task.quality = quality;
    task.status = MusicDownloadStatus.downloading;
    task.progress = 0.1;
    notifyListeners();

    // 2. Download Cover Art
    String localCoverPath = '';
    if (track.coverUrl.isNotEmpty) {
      try {
        final safeId = _sanitizeFilename(track.id);
        final coverFile = File(p.join(_coversDir!.path, '$safeId.jpg'));
        if (await coverFile.exists() && await coverFile.length() > 100) {
          localCoverPath = coverFile.path;
        } else {
          final client = HttpClient();
          final req = await client.getUrl(Uri.parse(track.coverUrl));
          final res = await req.close();
          if (res.statusCode == 200) {
            final bytes = await consolidateHttpClientResponseBytes(res);
            if (bytes.isNotEmpty) {
              await coverFile.writeAsBytes(bytes);
              localCoverPath = coverFile.path;
            }
          }
        }
      } catch (e) {
        debugPrint('[MusicDownloadService] Cover download warning: $e');
      }
    }

    // 3. Download Audio Stream Bytes
    final safeId = _sanitizeFilename(track.id);
    final targetFile = File(p.join(_tracksDir!.path, '$safeId.$format'));
    final tempFile = File(p.join(_tracksDir!.path, '$safeId.$format.tmp'));

    try {
      final client = HttpClient();
      final uri = Uri.parse(streamUrl);
      final request = await client.getUrl(uri);

      headers.forEach((k, v) => request.headers.set(k, v));

      final response = await request.close();
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('HTTP response code ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      task.totalBytes = contentLength > 0 ? contentLength : 0;

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final sink = tempFile.openWrite();
      int received = 0;

      await for (final chunk in response) {
        if (task.status == MusicDownloadStatus.cancelled) {
          await sink.close();
          if (await tempFile.exists()) await tempFile.delete();
          return;
        }

        sink.add(chunk);
        received += chunk.length;
        task.bytesDownloaded = received;

        if (contentLength > 0) {
          // Progress from 0.1 to 0.98
          task.progress = 0.1 + (0.88 * (received / contentLength));
        }
        notifyListeners();
      }

      await sink.flush();
      await sink.close();

      // Atomic rename
      if (await targetFile.exists()) await targetFile.delete();
      await tempFile.rename(targetFile.path);

      final finalSize = await targetFile.length();

      // 4. Save Downloaded Metadata Record
      final downloadedRecord = DownloadedMusicTrack(
        id: track.id,
        title: track.title,
        artist: track.artist,
        artistId: track.artistId,
        album: track.album,
        albumId: track.albumId,
        coverUrl: track.coverUrl,
        durationSeconds: track.durationSeconds,
        explicit: track.explicit,
        localAudioPath: targetFile.path,
        localCoverPath: localCoverPath,
        format: format,
        quality: quality,
        fileSizeBytes: finalSize,
        downloadedAt: DateTime.now(),
        trackNumber: track.trackNumber,
      );

      _downloadedTracks.removeWhere((t) => t.id == track.id);
      _downloadedTracks.insert(0, downloadedRecord);
      await _saveDownloadedTracks();

      task.status = MusicDownloadStatus.completed;
      task.progress = 1.0;
      notifyListeners();
    } catch (e) {
      debugPrint('[MusicDownloadService] Download failed for ${track.title}: $e');
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      task.status = MusicDownloadStatus.failed;
      task.errorMessage = 'Download error: ${e.toString()}';
      notifyListeners();
    }
  }

  String _sanitizeFilename(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> _saveDownloadedTracks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_downloadedTracks.map((t) => t.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (e) {
      debugPrint('[MusicDownloadService] Save error: $e');
    }
  }
}
