import 'package:flutter/material.dart';

import '../../iptv/playtorrio_tv/data/iptv_network.dart';
import '../../services/iptv/iptv_controller_service.dart';
import '../../services/iptv/iptv_favorites_service.dart';
import 'iptv_live_player_page.dart';
import 'iptv_playlists_page.dart';

class IptvPage extends StatefulWidget {
  const IptvPage({super.key});

  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> {
  late final IptvControllerService _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = IptvControllerService()..initialize();
    _ctrl.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portal = _ctrl.activePortal;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        leading: portal != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => _ctrl.closePortal(),
              )
            : null,
        title: Text(portal?.name ?? 'Live TV'),
        actions: [
          IconButton(
            tooltip: 'M3U Playlists',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IptvPlaylistsPage()),
            ),
            icon: const Icon(Icons.playlist_play_rounded),
          ),
        ],
      ),
      body: portal == null ? _buildScraperHub() : _buildPortalBrowser(),
    );
  }

  Widget _buildScraperHub() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF12151E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'IPTV Portal Scraper',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _ctrl.scrapeStatus.isEmpty
                    ? 'Discover Xtream portals from public catalogs, verify them, then browse Live TV and star channels for your Home guide.'
                    : _ctrl.scrapeStatus,
                style: const TextStyle(color: Colors.white54, height: 1.4),
              ),
              if (_ctrl.scrapeError != null) ...[
                const SizedBox(height: 8),
                Text(_ctrl.scrapeError!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _ctrl.scraping ? null : () => _ctrl.scrapeMore(),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: Text(_ctrl.scraping ? 'Scanning…' : 'Scan Catalog'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C5CFF)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _ctrl.verifying || _ctrl.scrapedPortals.isEmpty
                        ? null
                        : () => _ctrl.verifyScraped(),
                    icon: const Icon(Icons.verified_rounded, size: 18),
                    label: Text(_ctrl.verifying ? 'Verifying…' : 'Verify Portals'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Verified portals (${_ctrl.verifiedPortals.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 10),
        if (_ctrl.verifiedPortals.isEmpty)
          const Text('No verified portals yet. Scan and verify to browse Live TV.',
              style: TextStyle(color: Colors.white54))
        else
          ..._ctrl.verifiedPortals.map((portal) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_rounded, color: Color(0xFF7C5CFF)),
                title: Text(portal.name),
                subtitle: Text('Expires ${portal.expiry}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _ctrl.openPortal(portal),
              )),
      ],
    );
  }

  Widget _buildPortalBrowser() {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _categoryChip('All', ''),
              ..._ctrl.categories.map(
                (c) => _categoryChip(c.name, c.id),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ctrl.loadingBrowse
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C5CFF)))
              : ListView.builder(
                  itemCount: _ctrl.streams.length,
                  itemBuilder: (context, index) {
                    final stream = _ctrl.streams[index];
                    final portal = _ctrl.activePortal!;
                    final starred = _ctrl.isBrowserFavorite(stream);
                    return ListTile(
                      leading: stream.icon.isNotEmpty
                          ? Image.network(stream.icon, width: 48, height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.live_tv))
                          : const Icon(Icons.live_tv, color: Color(0xFF7C5CFF)),
                      title: Text(stream.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: Icon(
                          starred ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: starred ? const Color(0xFFFFC107) : Colors.white38,
                        ),
                        onPressed: () async {
                          await _ctrl.toggleBrowserFavorite(stream);
                          await IptvFavoritesService.instance.togglePortalFavorite(
                            portal: portal,
                            stream: stream,
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IptvLivePlayerPage(
                              title: stream.name,
                              streamUrl: IptvClient.streamUrl(portal.portal, stream),
                              logoUrl: stream.icon.isEmpty ? null : stream.icon,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _categoryChip(String label, String id) {
    final selected = _ctrl.selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _ctrl.selectCategory(id),
        selectedColor: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
      ),
    );
  }
}
