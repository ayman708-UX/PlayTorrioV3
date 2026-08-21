import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Lightweight live stream player for IPTV channels (M3U or portal URLs).
class IptvLivePlayerPage extends StatefulWidget {
  final String title;
  final String streamUrl;
  final String? logoUrl;

  const IptvLivePlayerPage({
    super.key,
    required this.title,
    required this.streamUrl,
    this.logoUrl,
  });

  @override
  State<IptvLivePlayerPage> createState() => _IptvLivePlayerPageState();
}

class _IptvLivePlayerPageState extends State<IptvLivePlayerPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.streamUrl),
        httpHeaders: const {
          'User-Agent':
              'VLC/3.0.20 LibVLC/3.0.20',
        },
      );
      await controller.initialize();
      await controller.play();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Color(0xFF7C5CFF))
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio == 0
                        ? 16 / 9
                        : _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
      ),
    );
  }
}
