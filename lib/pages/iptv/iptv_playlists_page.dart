import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../iptv/playtorrio_tv/m3u/m3u_models.dart';
import '../../iptv/playtorrio_tv/m3u/m3u_parser.dart';
import '../../iptv/playtorrio_tv/m3u/m3u_store.dart';
import '../../services/iptv/iptv_favorites_service.dart';
import '../iptv/iptv_live_player_page.dart';

class IptvPlaylistsPage extends StatefulWidget {
  const IptvPlaylistsPage({super.key});

  @override
  State<IptvPlaylistsPage> createState() => _IptvPlaylistsPageState();
}

class _IptvPlaylistsPageState extends State<IptvPlaylistsPage> {
  List<M3uPlaylist> _playlists = [];
  bool _loading = true;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await M3uStore.loadAll();
    if (!mounted) return;
    setState(() {
      _playlists = list;
      _loading = false;
    });
  }

  Future<void> _addFromUrl() async {
    final urlCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151822),
        title: const Text('Add M3U Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(hintText: 'Playlist name (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(hintText: 'https://example.com/list.m3u'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved != true) return;

    try {
      final channels = await M3uFetcher.fetchAndParse(urlCtrl.text.trim());
      final now = DateTime.now().millisecondsSinceEpoch;
      final playlist = M3uPlaylist(
        id: M3uStore.newId(),
        name: nameCtrl.text.trim().isEmpty ? 'M3U Playlist' : nameCtrl.text.trim(),
        sourceUrl: urlCtrl.text.trim(),
        addedAt: now,
        updatedAt: now,
        channels: channels,
      );
      _playlists = [..._playlists, playlist];
      await M3uStore.saveAll(_playlists);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load playlist: $e')),
        );
      }
    }
  }

  Future<void> _addFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final content = await File(result.files.single.path!).readAsString();
      final channels = M3uParser.parse(content);
      final now = DateTime.now().millisecondsSinceEpoch;
      final name = result.files.single.name;
      final playlist = M3uPlaylist(
        id: M3uStore.newId(),
        name: name,
        sourceUrl: null,
        addedAt: now,
        updatedAt: now,
        channels: channels,
      );
      _playlists = [..._playlists, playlist];
      await M3uStore.saveAll(_playlists);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse file: $e')),
        );
      }
    }
  }

  Future<void> _deletePlaylist(M3uPlaylist playlist) async {
    _playlists = _playlists.where((p) => p.id != playlist.id).toList();
    await M3uStore.saveAll(_playlists);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        title: const Text('M3U Playlists'),
        actions: [
          IconButton(onPressed: _addFromFile, icon: const Icon(Icons.upload_file_rounded)),
          IconButton(onPressed: _addFromUrl, icon: const Icon(Icons.link_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C5CFF)))
          : _playlists.isEmpty
              ? const Center(
                  child: Text(
                    'Add an M3U playlist by URL or file.\nStar channels to show them on Home.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final expanded = _expandedId == playlist.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12151E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(playlist.name),
                            subtitle: Text('${playlist.channels.length} channels'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                                  onPressed: () => setState(() {
                                    _expandedId = expanded ? null : playlist.id;
                                  }),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _deletePlaylist(playlist),
                                ),
                              ],
                            ),
                          ),
                          if (expanded)
                            ...playlist.channels.take(200).map((channel) {
                              return ValueListenableBuilder(
                                valueListenable: IptvFavoritesService.instance.favorites,
                                builder: (context, favs, _) {
                                  final id = 'm3u:${playlist.id}:${channel.url.hashCode}';
                                  final starred = favs.any((f) => f.id == id);
                                  return ListTile(
                                    dense: true,
                                    leading: channel.logo.isNotEmpty
                                        ? Image.network(channel.logo, width: 40, height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.live_tv))
                                        : const Icon(Icons.live_tv, color: Color(0xFF7C5CFF)),
                                    title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: channel.group.isNotEmpty ? Text(channel.group) : null,
                                    trailing: IconButton(
                                      icon: Icon(
                                        starred ? Icons.star_rounded : Icons.star_outline_rounded,
                                        color: starred ? const Color(0xFFFFC107) : Colors.white38,
                                      ),
                                      onPressed: () => IptvFavoritesService.instance.toggleM3uFavorite(
                                        playlist: playlist,
                                        channel: channel,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => IptvLivePlayerPage(
                                            title: channel.name,
                                            streamUrl: channel.url,
                                            logoUrl: channel.logo.isEmpty ? null : channel.logo,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            }),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
