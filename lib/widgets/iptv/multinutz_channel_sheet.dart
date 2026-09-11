import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../services/iptv/iptv_network.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../models/iptv/iptv_models.dart';
import '../../pages/iptv/iptv_portal_browser_page.dart';

enum ChannelSheetTab { xtreme, m3u }

class MultiNutzChannelSheet extends StatefulWidget {
  final int cellIndex;
  final void Function(String streamUrl, String channelName) onChannelSelected;
  final ChannelSheetTab tabType;

  const MultiNutzChannelSheet({
    super.key,
    required this.cellIndex,
    required this.onChannelSelected,
    required this.tabType,
  });

  @override
  State<MultiNutzChannelSheet> createState() => _MultiNutzChannelSheetState();
}

class _MultiNutzChannelSheetState extends State<MultiNutzChannelSheet>
    with SingleTickerProviderStateMixin {
  final ctrl = IptvController.instance;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Widget-tree caches — cleared on data change, reused on reopen
  Widget? _cachedXtremeBody;
  Widget? _cachedM3uBody;

  void _clearXtremeCache() { _cachedXtremeBody = null; }
  void _clearM3uCache() { _cachedM3uBody = null; }

  // Portal management state
  bool _showAddForm = false;
  bool _isPortalsEditMode = false;
  final Set<String> _selectedPortalKeys = {};
  String _portalSourceFilter = 'all';


  // M3U management state
  bool _showM3uForm = false;
  bool _isM3uEditMode = false;
  final Set<String> _selectedM3uIds = {};

  // Add form controllers
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _m3uNameCtrl = TextEditingController();
  final _m3uUrlCtrl = TextEditingController();

  List<PortalChannelGroup> get _filteredXtremeGroups {
    if (_searchQuery.isEmpty) return ctrl.xtremeGroups;
    final q = _searchQuery.toLowerCase();
    return ctrl.xtremeGroups
        .map((group) {
          final filteredHits = group.hits
              .where((hit) =>
                  hit.stream.name.toLowerCase().contains(q) ||
                  group.portal.name.toLowerCase().contains(q))
              .toList();
          if (filteredHits.isEmpty) return null;
          return PortalChannelGroup(portal: group.portal, hits: filteredHits);
        })
        .whereType<PortalChannelGroup>()
        .toList();
  }

  List<M3uChannelGroup> get _filteredM3uGroups {
    if (_searchQuery.isEmpty) return ctrl.m3uGroups;
    final q = _searchQuery.toLowerCase();
    return ctrl.m3uGroups
        .map((group) {
          final filtered = group.channels
              .where((ch) =>
                  ch.name.toLowerCase().contains(q) ||
                  group.playlist.name.toLowerCase().contains(q))
              .toList();
          if (filtered.isEmpty) return null;
          return M3uChannelGroup(playlist: group.playlist, channels: filtered);
        })
        .whereType<M3uChannelGroup>()
        .toList();
  }

  List<VerifiedPortal> get _filteredPortals {
    return ctrl.verified.where((p) {
      if (_portalSourceFilter == 'fav') return ctrl.isFavoritePortal(p.key);
      final src = p.portal.source.toLowerCase();
      if (_portalSourceFilter == 'custom') {
        return src.isEmpty || src.contains('custom') || src.contains('manual');
      }
      if (_portalSourceFilter == 'cloud') {
        return src.contains('cloud') || src.contains('vault');
      }
      if (_portalSourceFilter == 'reddit') {
        return src.contains('reddit');
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.tabType == ChannelSheetTab.xtreme) {
      ctrl.xtremeGroups;
    } else {
      ctrl.m3uGroups;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _m3uNameCtrl.dispose();
    _m3uUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAddPortal() async {
    final success = await ctrl.addManual(
      url: _urlCtrl.text,
      username: _userCtrl.text,
      password: _passCtrl.text,
    );
    if (success && mounted) {
      _urlCtrl.clear();
      _userCtrl.clear();
      _passCtrl.clear();
      setState(() => _showAddForm = false);
      _clearXtremeCache();
    }
  }

  Future<void> _submitAddM3u() async {
    if (_m3uUrlCtrl.text.trim().isEmpty) return;
    await ctrl.addM3uFromUrl(_m3uNameCtrl.text, _m3uUrlCtrl.text.trim());
    if (mounted) {
      _m3uNameCtrl.clear();
      _m3uUrlCtrl.clear();
      setState(() => _showM3uForm = false);
      _clearM3uCache();
    }
  }

  Future<void> _deleteSelectedPortals() async {
    if (_selectedPortalKeys.isEmpty) return;
    final count = _selectedPortalKeys.length;
    final toDelete = Set<String>.from(_selectedPortalKeys);
    setState(() {
      _selectedPortalKeys.clear();
      _isPortalsEditMode = false;
    });
    await ctrl.deletePortalsByKeys(toDelete);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $count portal${count == 1 ? "" : "s"}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E2235),
        ),
      );
    }
    _clearXtremeCache();
  }

  Future<void> _deleteAllPortals() async {
    final count = ctrl.verified.length;
    setState(() {
      _selectedPortalKeys.clear();
      _isPortalsEditMode = false;
    });
    await ctrl.deleteAllPortals();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed all $count portals'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E2235),
        ),
      );
    }
    _clearXtremeCache();
  }

  Future<void> _deleteSelectedM3u() async {
    if (_selectedM3uIds.isEmpty) return;
    final count = _selectedM3uIds.length;
    final toDelete = Set<String>.from(_selectedM3uIds);
    setState(() {
      _selectedM3uIds.clear();
      _isM3uEditMode = false;
    });
    for (final id in toDelete) {
      await ctrl.deleteM3uPlaylist(id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $count playlist${count == 1 ? "" : "s"}'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E2235),
        ),
      );
    }
    _clearM3uCache();
  }

  Future<void> _deleteAllM3u() async {
    final count = ctrl.m3uPlaylists.length;
    setState(() {
      _selectedM3uIds.clear();
      _isM3uEditMode = false;
    });
    await ctrl.deleteAllM3uPlaylists();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed all $count playlists'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF1E2235),
        ),
      );
    }
  }

  Widget _buildSourceChip(
    String filterKey,
    String label,
    IconData icon,
    AppThemePalette palette, {
    Color? activeColor,
  }) {
    final isSelected = _portalSourceFilter == filterKey;
    final color = activeColor ?? palette.primaryColor;

    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 14,
        color: isSelected ? Colors.white : Colors.white60,
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.3),
      backgroundColor: const Color(0xFF141722),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.08),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _portalSourceFilter = filterKey;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0C0F17),
      child: widget.tabType == ChannelSheetTab.xtreme ? _buildXtremeTab() : _buildM3uTab(),
    );
  }

  Widget _buildXtremeTab() {
    final palette = AppThemeService.currentPalette.value;
    final groups = _filteredXtremeGroups;
    final portals = _filteredPortals;
    final allSelected = portals.isNotEmpty && _selectedPortalKeys.length == portals.length;

    // Return cached body when not searching — avoids rebuilding all ExpansionTiles
    if (_searchQuery.isEmpty && _cachedXtremeBody != null) {
      return _cachedXtremeBody!;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search channels...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.primaryColor),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),

        // Action Buttons Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: ctrl.isScraping
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.radar_rounded, size: 16, color: Colors.white),
                label: Text(
                  ctrl.isScraping ? 'Finding…' : 'Generate',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                onPressed: ctrl.isScraping ? null : ctrl.scrape,
              ),

              PopupMenuButton<CatalogSource>(
                tooltip: 'Choose Portal Source',
                initialValue: ctrl.scrapeSource,
                onSelected: (s) {
                  ctrl.setScrapeSource(s);
                  setState(() {});
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                color: const Color(0xFF161A26),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ctrl.scrapeSource == CatalogSource.cloudVault
                            ? Icons.cloud_done_rounded
                            : Icons.forum_rounded,
                        size: 14,
                        color: ctrl.scrapeSource == CatalogSource.cloudVault
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFFF5722),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        ctrl.scrapeSource == CatalogSource.cloudVault ? 'Cloud Vault' : 'Reddit',
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.white70),
                    ],
                  ),
                ),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: CatalogSource.cloudVault,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_done_rounded, color: Color(0xFF00E5FF), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Row(
                                children: [
                                  Text('Cloud Vault', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  SizedBox(width: 6),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    child: Text('9.6k+', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9.5, fontWeight: FontWeight.w800)),
                                  ),
                                 ],
                               ),
                             ],
                           ),
                          ),
                        ],
                      ),
),
                  PopupMenuItem(
                    value: CatalogSource.reddit,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.forum_rounded, color: Color(0xFFFF5722), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Reddit Communities', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              const Text('Live shared pastes from subreddits', style: TextStyle(color: Colors.white60, fontSize: 10.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Portal', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              onPressed: () => setState(() => _showAddForm = !_showAddForm),
            ),
            if (ctrl.verified.isNotEmpty)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isPortalsEditMode ? const Color(0xFF00D2EF) : Colors.white,
                  side: BorderSide(color: _isPortalsEditMode ? const Color(0xFF00D2EF) : Colors.white.withValues(alpha: 0.2)),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(_isPortalsEditMode ? Icons.edit_off_rounded : Icons.edit_rounded, size: 15),
                label: Text(_isPortalsEditMode ? 'Done' : 'Manage', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                onPressed: () {
                  setState(() {
                    _isPortalsEditMode = !_isPortalsEditMode;
                    if (!_isPortalsEditMode) _selectedPortalKeys.clear();
                  });
                },
              ),
          ],
        ),
        ),

        // Selection Toolbar for Portals
        if (_isPortalsEditMode && ctrl.verified.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: palette.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.primaryColor.withValues(alpha: 0.3)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                          size: 17,
                          color: const Color(0xFF00D2EF),
                        ),
                        label: Text(
                          allSelected ? 'Deselect All' : 'Select All',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        onPressed: () {
                          setState(() {
                            if (allSelected) {
                              _selectedPortalKeys.clear();
                            } else {
                              _selectedPortalKeys.clear();
                              _selectedPortalKeys.addAll(portals.map((v) => v.key));
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${_selectedPortalKeys.length}/${portals.length})',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.delete_rounded, size: 14),
                        label: Text(
                          'Delete (${_selectedPortalKeys.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _selectedPortalKeys.isEmpty ? null : _deleteSelectedPortals,
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _deleteAllPortals,
                        child: const Text('Delete All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        if (ctrl.statusText.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              ctrl.statusText,
              style: const TextStyle(color: Color(0xFF00D2EF), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],

        // Add Manual Portal Form
        if (_showAddForm) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Xtream Codes Portal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _urlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Server URL (e.g. http://example.com:8080)', isDense: true, border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _userCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Username', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _passCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Password', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  if (ctrl.addError != null) ...[
                    const SizedBox(height: 6),
                    Text(ctrl.addError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C5CFF)),
                      onPressed: ctrl.isAdding ? null : _submitAddPortal,
                      child: ctrl.isAdding
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Verify & Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 8),

        // Source Filter Bar
        if (ctrl.verified.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildSourceChip('all', 'All (${ctrl.verified.length})', Icons.apps_rounded, palette),
                  const SizedBox(width: 6),
                  _buildSourceChip('custom', 'My Portals (${ctrl.verified.where((p) {
                    final s = p.portal.source.toLowerCase();
                    return s.isEmpty || s.contains('custom') || s.contains('manual');
                  }).length})', Icons.lock_rounded, palette, activeColor: const Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  _buildSourceChip('cloud', 'Cloud Vault (${ctrl.verified.where((p) => p.portal.source.toLowerCase().contains('cloud') || p.portal.source.toLowerCase().contains('vault')).length})', Icons.cloud_done_rounded, palette, activeColor: const Color(0xFF00E5FF)),
                  const SizedBox(width: 6),
                  _buildSourceChip('reddit', 'Reddit (${ctrl.verified.where((p) => p.portal.source.toLowerCase().contains('reddit')).length})', Icons.forum_rounded, palette, activeColor: const Color(0xFFFF5722)),
                  const SizedBox(width: 6),
                  _buildSourceChip('fav', 'Favorites ⭐ (${ctrl.verified.where((p) => ctrl.isFavoritePortal(p.key)).length})', Icons.star_rounded, palette, activeColor: const Color(0xFFFFC107)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Portal List
        ...[
          if (portals.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tv_off_rounded, size: 48, color: Colors.white24),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isEmpty ? 'No Xtream portals loaded' : 'No matching channels',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            )
          else if (!_isPortalsEditMode && _searchQuery.isEmpty)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: portals.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final p = portals[index];
                  return _buildXtremePortalCard(p, palette);
                },
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _buildPortalChannelGroup(group, palette);
                },
              ),
            ),
        ],
      ],
    );
    if (_searchQuery.isEmpty) _cachedXtremeBody = body;
    return body;
  }

  Widget _buildXtremePortalCard(VerifiedPortal p, AppThemePalette palette) {
    final showExp = IptvSettings.showPortalExpiry.value && p.expiry.isNotEmpty;
    final showConn = IptvSettings.showPortalConnections.value && p.maxConnections.isNotEmpty;
    final isFav = ctrl.isFavoritePortal(p.key);
    final hasBadges = showExp || showConn || p.portal.source.isNotEmpty;
    final isSelected = _isPortalsEditMode && _selectedPortalKeys.contains(p.key);

    Widget buildCopyBtn() {
      return IconButton(
        icon: const Icon(Icons.copy_rounded, color: Colors.white60, size: 17),
        tooltip: 'Copy Login (url:user:pass)',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () {
          final text = '${p.portal.url}:${p.portal.username}:${p.portal.password}';
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied: $text'),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF1E2235),
            ),
          );
        },
      );
    }

    Widget buildFavBtn() {
      return IconButton(
        icon: Icon(
          isFav ? Icons.star_rounded : Icons.star_outline_rounded,
          color: isFav ? const Color(0xFFFFC107) : Colors.white38,
          size: 19,
        ),
        tooltip: isFav ? 'Remove Favorite' : 'Add to Favorites',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () => ctrl.toggleFavoritePortal(p.key),
      );
    }

    Widget buildDeleteBtn() {
      return IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
        tooltip: 'Remove Portal',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () => ctrl.deletePortalsByKeys({p.key}),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (_isPortalsEditMode) {
            setState(() {
              if (isSelected) _selectedPortalKeys.remove(p.key);
              else _selectedPortalKeys.add(p.key);
            });
} else {
            Navigator.push(
              context,
              materialRoute(
                builder: (_) => IptvPortalBrowserPage(
                  portal: p,
                  returning: true,
                  onStreamSelected: widget.onChannelSelected,
                ),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? palette.primaryColor.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? palette.primaryColor : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_isPortalsEditMode)
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? palette.primaryColor : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? palette.primaryColor : Colors.white38, width: 2),
                      ),
                      child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
                    )
                  else
                    const SizedBox(width: 18, height: 8, child: DecoratedBox(decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle))),
                  Expanded(
                    child: Text(
                      p.name.isNotEmpty ? p.name : p.portal.url,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!_isPortalsEditMode) ...[
                    const SizedBox(width: 4),
                    buildCopyBtn(),
                    const SizedBox(width: 2),
                    buildFavBtn(),
                    const SizedBox(width: 2),
                    buildDeleteBtn(),
                  ],
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.link_rounded, size: 13, color: Colors.white38),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.portal.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                    ),
                  ),
                ],
              ),
              if (hasBadges) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (showExp)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: palette.primaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Exp: ${p.expiry}', style: TextStyle(color: palette.primaryColor, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                          if (showConn)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Conn: ${p.activeConnections}/${p.maxConnections}', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                          if (p.portal.source.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: p.portal.source.toLowerCase().contains('cloud') || p.portal.source.toLowerCase().contains('vault')
                                    ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                                    : (p.portal.source.toLowerCase().contains('reddit')
                                        ? const Color(0xFFFF5722).withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.08)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                p.portal.source,
                                style: TextStyle(
                                  color: p.portal.source.toLowerCase().contains('cloud') || p.portal.source.toLowerCase().contains('vault')
                                      ? const Color(0xFF00E5FF)
                                      : (p.portal.source.toLowerCase().contains('reddit')
                                          ? const Color(0xFFFF7043)
                                          : Colors.white70),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
],
                      ),
                    ),
                  ],
                ),
              ],

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortalChannelGroup(PortalChannelGroup group, AppThemePalette palette) {
    final isRich = IptvSettings.portalCardStyle.value == PortalCardStyle.rich;
    final showExp = IptvSettings.showPortalExpiry.value && group.portal.expiry.isNotEmpty;
    final showConn = IptvSettings.showPortalConnections.value && group.portal.maxConnections.isNotEmpty;
    final isSelected = _isPortalsEditMode && _selectedPortalKeys.contains(group.portal.key);
    final isFav = ctrl.isFavoritePortal(group.portal.key);

    Widget buildCopyBtn() {
      return IconButton(
        icon: const Icon(Icons.copy_rounded, color: Colors.white60, size: 17),
        tooltip: 'Copy Login (url:user:pass)',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () {
          final text = '${group.portal.portal.url}:${group.portal.portal.username}:${group.portal.portal.password}';
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied: $text'),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF1E2235),
            ),
          );
        },
      );
    }

    Widget buildFavBtn() {
      return IconButton(
        icon: Icon(
          isFav ? Icons.star_rounded : Icons.star_outline_rounded,
          color: isFav ? const Color(0xFFFFC107) : Colors.white38,
          size: 19,
        ),
        tooltip: isFav ? 'Remove Favorite' : 'Add to Favorites',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () => ctrl.toggleFavoritePortal(group.portal.key),
      );
    }

    Widget buildDeleteBtn() {
      return IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
        tooltip: 'Remove Portal',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () => ctrl.deletePortalsByKeys({group.portal.key}),
      );
    }

    Widget buildBadgesWrap() {
      return Wrap(
        spacing: 5,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showExp)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: palette.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Exp: ${group.portal.expiry}',
                style: TextStyle(color: palette.primaryColor, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          if (showConn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Conn: ${group.portal.activeConnections}/${group.portal.maxConnections}',
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
          if (group.portal.portal.source.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: group.portal.portal.source.toLowerCase().contains('cloud') || group.portal.portal.source.toLowerCase().contains('vault')
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                    : (group.portal.portal.source.toLowerCase().contains('reddit')
                        ? const Color(0xFFFF5722).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.08)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                group.portal.portal.source,
                style: TextStyle(
                  color: group.portal.portal.source.toLowerCase().contains('cloud') || group.portal.portal.source.toLowerCase().contains('vault')
                      ? const Color(0xFF00E5FF)
                      : (group.portal.portal.source.toLowerCase().contains('reddit')
                          ? const Color(0xFFFF7043)
                          : Colors.white70),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      );
    }

    return ExpansionTile(
      collapsedShape: const RoundedRectangleBorder(),
      shape: const RoundedRectangleBorder(side: BorderSide(color: Color(0x1AFFFFFF))),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      title: Row(
        children: [
          if (_isPortalsEditMode)
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isSelected ? palette.primaryColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? palette.primaryColor : Colors.white38, width: 2),
              ),
              child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
            )
          else
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.portal.name.isNotEmpty ? group.portal.name : group.portal.portal.url,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_isPortalsEditMode) ...[
                      const SizedBox(width: 4),
                      buildCopyBtn(),
                      const SizedBox(width: 2),
                      buildFavBtn(),
                      const SizedBox(width: 2),
                      buildDeleteBtn(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  group.portal.portal.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
                ),
                if ((showExp || showConn || group.portal.portal.source.isNotEmpty) && isRich) ...[
                  const SizedBox(height: 4),
                  buildBadgesWrap(),
                ],
              ],
            ),
          ),
          if ((_isPortalsEditMode || !(showExp || showConn || group.portal.portal.source.isNotEmpty) || !isRich))
            const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
        ],
      ),
      children: group.hits.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No live channels available for this portal',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
                ),
              ),
            ]
          : [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '${group.hits.length} live channels',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 320),
                 child: ListView.separated(
                   shrinkWrap: false,
                   physics: const ClampingScrollPhysics(),
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                   itemCount: group.hits.length,
                   separatorBuilder: (_, _) => const SizedBox(height: 4),
                   itemBuilder: (context, hitIndex) {
                     final hit = group.hits[hitIndex];
                     return _buildChannelHitItem(hit, hitIndex);
                   },
                 ),
               ),
            ],
    );
  }

  Widget _buildChannelHitItem(ChannelHit hit, int hitIndex) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: hit.stream.icon.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(hit.stream.icon, width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.white30)),
              )
            : const Icon(Icons.tv, color: Colors.white30, size: 24),
        title: Text(
          hit.stream.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          hit.stream.containerExt.toUpperCase(),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        tileColor: Colors.white.withValues(alpha: 0.04),
        hoverColor: Colors.white.withValues(alpha: 0.08),
        onTap: () {
          Navigator.pop(context);
          widget.onChannelSelected(hit.streamUrl, hit.stream.name);
        },
      ),
    );
  }

  Widget _buildM3uTab() {
    final palette = AppThemeService.currentPalette.value;
    final groups = _filteredM3uGroups;
    final allSelected = ctrl.m3uPlaylists.isNotEmpty && _selectedM3uIds.length == ctrl.m3uPlaylists.length;

    // Return cached body when not searching — avoids rebuilding all ExpansionTiles
    if (_searchQuery.isEmpty && _cachedM3uBody != null) {
      return _cachedM3uBody!;
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search channels...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white24),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.primaryColor),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),

        // Action Buttons Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.playlist_add_rounded, size: 17, color: Colors.white),
                label: const Text('Add M3U URL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                onPressed: () => setState(() => _showM3uForm = !_showM3uForm),
              ),
              if (ctrl.m3uPlaylists.isNotEmpty) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isM3uEditMode ? const Color(0xFF00D2EF) : Colors.white,
                    side: BorderSide(color: _isM3uEditMode ? const Color(0xFF00D2EF) : Colors.white.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(_isM3uEditMode ? Icons.edit_off_rounded : Icons.edit_rounded, size: 15),
                  label: Text(_isM3uEditMode ? 'Done' : 'Manage', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      _isM3uEditMode = !_isM3uEditMode;
                      if (!_isM3uEditMode) _selectedM3uIds.clear();
                    });
                  },
                ),
              ],
            ],
          ),
        ),

        // Selection Toolbar for M3U
        if (_isM3uEditMode && ctrl.m3uPlaylists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: palette.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.primaryColor.withValues(alpha: 0.3)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                          size: 17,
                          color: const Color(0xFF00D2EF),
                        ),
                        label: Text(
                          allSelected ? 'Deselect All' : 'Select All',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        onPressed: () {
                          setState(() {
                            if (allSelected) {
                              _selectedM3uIds.clear();
                            } else {
                              _selectedM3uIds.clear();
                              _selectedM3uIds.addAll(ctrl.m3uPlaylists.map((pl) => pl.id));
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${_selectedM3uIds.length}/${ctrl.m3uPlaylists.length})',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.delete_rounded, size: 14),
                        label: Text(
                          'Delete (${_selectedM3uIds.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _selectedM3uIds.isEmpty ? null : _deleteSelectedM3u,
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _deleteAllM3u,
                        child: const Text('Delete All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        // Add M3U Form
        if (_showM3uForm) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add M3U Playlist Subscription', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _m3uNameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'Playlist Name', isDense: true, border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _m3uUrlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(labelText: 'M3U / M3U8 URL', isDense: true, border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C5CFF)),
                      onPressed: ctrl.isM3uLoading ? null : _submitAddM3u,
                      child: ctrl.isM3uLoading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Fetch & Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 8),

        // Channel Groups List
        if (groups.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.playlist_play_rounded, size: 48, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isEmpty ? 'No M3U playlists loaded' : 'No matching channels',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _buildM3uChannelGroup(group, palette);
              },
            ),
          ),
      ],
    );
    if (_searchQuery.isEmpty) _cachedM3uBody = body;
    return body;
  }

  Widget _buildM3uChannelGroup(M3uChannelGroup group, AppThemePalette palette) {
    final isSelected = _isM3uEditMode && _selectedM3uIds.contains(group.playlist.id);

    Widget buildCopyBtn() {
      return IconButton(
        icon: const Icon(Icons.copy_rounded, color: Colors.white60, size: 17),
        tooltip: 'Copy Playlist URL',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () {
          final text = group.playlist.sourceUrl ?? '';
          if (text.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied: $text'),
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF1E2235),
              ),
            );
          }
        },
      );
    }

    Widget buildDeleteBtn() {
      return IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
        tooltip: 'Remove Playlist',
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
        onPressed: () => ctrl.deleteM3uPlaylist(group.playlist.id),
      );
    }

    return ExpansionTile(
      collapsedShape: const RoundedRectangleBorder(),
      shape: const RoundedRectangleBorder(side: BorderSide(color: Color(0x1AFFFFFF))),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      title: Row(
        children: [
          if (_isM3uEditMode)
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isSelected ? palette.primaryColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? palette.primaryColor : Colors.white38, width: 2),
              ),
              child: isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
            )
          else
            Container(
              margin: const EdgeInsets.only(right: 10),
              child: Icon(Icons.queue_music_rounded, color: palette.primaryColor, size: 19),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.playlist.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${group.channels.length} channels${group.playlist.sourceUrl != null ? ' · ${group.playlist.sourceUrl!}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                ),
              ],
            ),
          ),
          if (!_isM3uEditMode) ...[
            const SizedBox(width: 6),
            buildCopyBtn(),
            const SizedBox(width: 2),
            buildDeleteBtn(),
          ],
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
        ],
      ),
      children: group.channels.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No channels in this playlist',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
                ),
              ),
            ]
          : [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '${group.channels.length} channels',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 320),
                 child: ListView.separated(
                   shrinkWrap: false,
                   physics: const ClampingScrollPhysics(),
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                   itemCount: group.channels.length,
                   separatorBuilder: (_, _) => const SizedBox(height: 4),
                   itemBuilder: (context, chIndex) {
                  final ch = group.channels[chIndex];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onChannelSelected(ch.url, ch.name);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            if (ch.logo.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(ch.logo, width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.white30)),
                              )
                            else
                              const Icon(Icons.tv, color: Colors.white30, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ch.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                  ),
                                  if (ch.group.isNotEmpty)
                                    Text(
                                      ch.group,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_arrow_rounded, color: Color(0xFF10B981), size: 18),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              ),
            ],
    );
  }
}
