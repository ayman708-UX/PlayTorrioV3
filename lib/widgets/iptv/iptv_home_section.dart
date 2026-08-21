import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/iptv/iptv_favorite_channel.dart';
import '../../pages/iptv/iptv_live_player_page.dart';
import '../../pages/iptv/iptv_page.dart';
import '../../services/iptv/iptv_epg_settings.dart';
import '../../services/iptv/iptv_favorites_service.dart';

/// Home screen row for starred IPTV channels with an optional compact TV guide.
class IptvHomeSection extends StatefulWidget {
  const IptvHomeSection({super.key});

  @override
  State<IptvHomeSection> createState() => _IptvHomeSectionState();
}

class _IptvHomeSectionState extends State<IptvHomeSection> {
  List<IptvGuideEntry> _guide = [];
  bool _loadingGuide = false;

  @override
  void initState() {
    super.initState();
    IptvFavoritesService.instance.favorites.addListener(_onFavoritesChanged);
    IptvEpgSettings.showHomeTvGuide.addListener(_onGuideSettingChanged);
    _refreshGuide();
  }

  @override
  void dispose() {
    IptvFavoritesService.instance.favorites.removeListener(_onFavoritesChanged);
    IptvEpgSettings.showHomeTvGuide.removeListener(_onGuideSettingChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    _refreshGuide();
  }

  void _onGuideSettingChanged() {
    if (IptvEpgSettings.showHomeTvGuide.value) {
      _refreshGuide();
    } else if (mounted) {
      setState(() {
        _guide = [];
        _loadingGuide = false;
      });
    }
  }

  Future<void> _refreshGuide() async {
    if (!IptvEpgSettings.showHomeTvGuide.value) return;
    if (!mounted) return;
    setState(() => _loadingGuide = true);
    await IptvFavoritesService.instance.syncPortalBrowserFavorites();
    final guide = await IptvFavoritesService.instance.loadGuideEntries();
    if (!mounted) return;
    setState(() {
      _guide = guide;
      _loadingGuide = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: IptvEpgSettings.showHomeTvGuide,
      builder: (context, showGuide, _) {
        return ValueListenableBuilder(
          valueListenable: IptvFavoritesService.instance.favorites,
          builder: (context, favorites, __) {
            if (favorites.isEmpty) {
              return _emptyPrompt(context);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live TV Favorites',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Starred channels from M3U playlists and IPTV portals',
                              style: TextStyle(color: Colors.white54, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      if (showGuide)
                        IconButton(
                          tooltip: 'Refresh guide',
                          onPressed: _loadingGuide ? null : _refreshGuide,
                          icon: _loadingGuide
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, color: Colors.white54),
                        ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const IptvPage()),
                        ),
                        child: const Text('Manage'),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: favorites.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final channel = favorites[index];
                      final entry = showGuide && index < _guide.length
                          ? _guide[index]
                          : null;
                      return _ChannelCard(
                        channel: channel,
                        entry: entry,
                        showGuide: showGuide,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IptvLivePlayerPage(
                              title: channel.name,
                              streamUrl: channel.streamUrl,
                              logoUrl: channel.logoUrl,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (showGuide && _guide.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'TV Guide',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._guide.take(6).map((entry) => _GuideRow(entry: entry)),
                ],
                const SizedBox(height: 12),
              ],
            );
          },
        );
      },
    );
  }

  Widget _emptyPrompt(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF12151E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF7C5CFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.live_tv_rounded, color: Color(0xFF7C5CFF)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live TV', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                    'Add M3U playlists or scrape IPTV portals, then star channels to pin them here.',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IptvPage()),
              ),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final IptvFavoriteChannel channel;
  final IptvGuideEntry? entry;
  final bool showGuide;
  final VoidCallback onTap;

  const _ChannelCard({
    required this.channel,
    required this.entry,
    required this.showGuide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF12151E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: channel.logoUrl!,
                      width: 32,
                      height: 22,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.live_tv, size: 20),
                    ),
                  )
                else
                  const Icon(Icons.live_tv, color: Color(0xFF7C5CFF), size: 20),
                const Spacer(),
                const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
              ],
            ),
            const Spacer(),
            Text(
              channel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            if (showGuide && entry?.nowTitle != null) ...[
              const SizedBox(height: 4),
              Text(
                entry!.nowTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  final IptvGuideEntry entry;

  const _GuideRow({required this.entry});

  String _timeRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(start.hour)}:${two(start.minute)}–${two(end.hour)}:${two(end.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: const Icon(Icons.schedule_rounded, color: Color(0xFF7C5CFF), size: 20),
      title: Text(entry.channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.nowTitle != null
            ? 'Now: ${entry.nowTitle}${entry.nextTitle != null ? '  •  Next: ${entry.nextTitle}' : ''}'
            : (entry.nextTitle != null ? 'Next: ${entry.nextTitle}' : 'No guide data'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.nowStart != null
          ? Text(
              _timeRange(entry.nowStart, entry.nowStop),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            )
          : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IptvLivePlayerPage(
            title: entry.channel.name,
            streamUrl: entry.channel.streamUrl,
            logoUrl: entry.channel.logoUrl,
          ),
        ),
      ),
    );
  }
}
