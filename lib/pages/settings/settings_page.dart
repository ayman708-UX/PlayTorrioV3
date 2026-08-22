import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/addon/addon.dart';
import '../../models/debrid/debrid_account.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/debrid/debrid_service.dart';
import '../../services/glass_settings.dart';
import '../../services/player_settings.dart';
import '../../services/app_updater_service.dart';
import '../../services/trakt/trakt_auth_service.dart';
import '../../services/trakt/trakt_sync_service.dart';
import '../../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _manager = AddonManager.instance;
  bool _isAdding = false;
  bool _isCheckingForUpdates = false;

  Future<void> _checkForUpdates(BuildContext context) async {
    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final updater = AppUpdaterService();
      final updateInfo = await updater.checkForUpdates();

      if (!context.mounted) return;

      if (updateInfo != null) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PlayTorrio is up to date!'),
            backgroundColor: Color(0xFF7C5CFF),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking updates: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  Widget _buildUpdateSection() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final versionText = snapshot.hasData
            ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}'
            : 'Check for app updates';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF12151E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: Color(0xFF7C5CFF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App Updates',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      versionText,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _isCheckingForUpdates
                    ? null
                    : () => _checkForUpdates(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                child: _isCheckingForUpdates
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Check',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortcutsSection() {
    const shortcuts = [
      ('Space / K', 'Play / Pause'),
      ('J', 'Seek -5s'),
      ('L', 'Seek +5s'),
      ('M', 'Mute'),
      ('F', 'Toggle fullscreen'),
      ('Esc', 'Back'),
      ('Tab', 'Focus hub switcher'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.keyboard_rounded,
                  color: Color(0xFF7C5CFF),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final (key, action) in shortcuts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      key,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    action,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addons = _manager.addons;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: GlassSettings.enabled,
            builder: (context, enabled, _) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF12151E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: enabled
                        ? const Color(0xFF7C5CFF).withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.blur_on_rounded,
                        color: Color(0xFF7C5CFF),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Full Liquid Glass',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Real lenses, refraction, jelly and hover effects. Uses more GPU power.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: enabled,
                      onChanged: GlassSettings.setEnabled,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          // ── Player section ──
          ValueListenableBuilder<bool>(
            valueListenable: PlayerSettings.autoNextEnabled,
            builder: (context, autoNext, _) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF12151E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.skip_next_rounded,
                        color: Color(0xFF7C5CFF),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-Play Next Episode',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Show a countdown and auto-play the next episode at the end of credits.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch.adaptive(
                      value: autoNext,
                      onChanged: PlayerSettings.setAutoNextEnabled,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          // ── App Updates section ──
          _buildUpdateSection(),
          const SizedBox(height: 28),

          // ── Trakt section ──
          _buildTraktSection(),
          const SizedBox(height: 28),

          // ── Debrid Providers section ──
          _buildDebridSection(),
          const SizedBox(height: 28),

          // ── Shortcuts section ──
          _buildShortcutsSection(),
          const SizedBox(height: 28),

          // ── Section title ──
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  color: Color(0xFF7C5CFF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Metadata Addons',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Addons provide movie and series metadata for your home page. '
            'Enable multiple to see more content.',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withValues(alpha: 0.42),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),

          // ── Addon cards ──
          ...addons.map(
            (addon) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AddonCard(
                addon: addon,
                onToggle: (enabled) async {
                  await _manager.toggleAddon(addon.manifest.id, enabled);
                  setState(() {});
                },
                onRemove: () => _confirmRemove(addon),
              ),
            ),
          ),

          // ── Add addon button ──
          const SizedBox(height: 6),
          _AddAddonButton(isLoading: _isAdding, onTap: _addAddon),
        ],
      ),
    );
  }

  // ── Trakt section ──────────────────────────────────────────────────────

  Widget _buildTraktSection() {
    final traktAuth = TraktAuthService();

    return ValueListenableBuilder<bool>(
      valueListenable: traktAuth.isLoggedIn,
      builder: (context, loggedIn, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: traktAuth.isLoading,
          builder: (context, loading, _) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF12151E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: loggedIn
                      ? const Color(0xFFED1C24).withOpacity(0.25)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFED1C24).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sync_rounded, color: Color(0xFFED1C24)),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trakt',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Sync your watchlist with Trakt.tv',
                              style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      if (loggedIn)
                        TextButton(
                          onPressed: loading ? null : () => traktAuth.logout(),
                          child: Text(
                            'Disconnect',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                            ),
                          ),
                        )
                      else
                        ElevatedButton(
                          onPressed: loading ? null : () => traktAuth.authorize(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFED1C24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          child: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Connect',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                        ),
                    ],
                  ),
                  if (loggedIn) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await TraktSyncService.syncDown();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Synced with Trakt'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Color(0xFF1E8E3E),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Sync Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.08),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Debrid section ─────────────────────────────────────────────────────

  Widget _buildDebridSection() {
    final debrid = DebridService.instance;

    return ValueListenableBuilder<List<DebridAccount>>(
      valueListenable: debrid.accounts,
      builder: (context, accounts, _) {
        final rdAccount = debrid.getAccount(DebridProvider.realDebrid);
        final torboxAccount = debrid.getAccount(DebridProvider.torbox);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF12151E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D294).withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cloud_download_rounded,
                      color: Color(0xFF00D294),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Debrid Services',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'High-speed cached torrent streaming (Real-Debrid & Torbox)',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDebridTile(
                providerName: 'Real-Debrid',
                account: rdAccount,
                onConnect: () => _showDebridTokenDialog(DebridProvider.realDebrid),
                onDisconnect: () => debrid.removeAccount(DebridProvider.realDebrid),
              ),
              const SizedBox(height: 10),
              _buildDebridTile(
                providerName: 'Torbox',
                account: torboxAccount,
                onConnect: () => _showDebridTokenDialog(DebridProvider.torbox),
                onDisconnect: () => debrid.removeAccount(DebridProvider.torbox),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDebridTile({
    required String providerName,
    required DebridAccount? account,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    final isConnected = account != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF191D28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF00D294).withOpacity(0.3)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 18,
            color: isConnected ? const Color(0xFF00D294) : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                if (isConnected) ...[
                  const SizedBox(height: 2),
                  Text(
                    account.username != null ? 'Connected as ${account.username}' : 'Active API Token',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: isConnected ? onDisconnect : onConnect,
            style: TextButton.styleFrom(
              foregroundColor: isConnected ? Colors.redAccent : const Color(0xFF00D294),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
            child: Text(isConnected ? 'Disconnect' : 'Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDebridTokenDialog(DebridProvider provider) async {
    final controller = TextEditingController();
    final debrid = DebridService.instance;

    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Connect ${provider.displayName}',
          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste your ${provider.displayName} API token/key to enable instant cloud stream resolving.',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'API Key / Token',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: const Color(0xFF0D1017),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D294),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save & Verify', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (token != null && token.isNotEmpty) {
      bool success = false;
      if (provider == DebridProvider.realDebrid) {
        success = await debrid.authenticateRealDebrid(token);
      } else if (provider == DebridProvider.torbox) {
        success = await debrid.authenticateTorbox(token);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '${provider.displayName} connected successfully!'
                  : 'Failed to verify token for ${provider.displayName}.',
            ),
            backgroundColor: success ? const Color(0xFF1E8E3E) : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Add addon flow ──────────────────────────────────────────────────────

  Future<void> _addAddon() async {
    final url = await _showAddDialog();
    if (url == null || url.trim().isEmpty) return;

    setState(() => _isAdding = true);

    try {
      final addon = await _manager.addAddon(url);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${addon.manifest.name} installed!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E8E3E),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<String?> _showAddDialog() {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151822),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Add Metadata Addon',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste the Stremio addon manifest URL.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'https://addon.example.com/manifest.json',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.22),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0D1017),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF7C5CFF)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Install',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Remove confirmation ─────────────────────────────────────────────────

  void _confirmRemove(InstalledAddon addon) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151822),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Remove ${addon.manifest.name}?'),
          content: Text(
            'Its catalogs will be removed from your home page.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _manager.removeAddon(addon.manifest.id);
                setState(() {});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Remove',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Addon Card
// ─────────────────────────────────────────────────────────────────────────────

class _AddonCard extends StatelessWidget {
  final InstalledAddon addon;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  const _AddonCard({
    required this.addon,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final m = addon.manifest;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: addon.enabled
              ? const Color(0xFF7C5CFF).withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.14),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  color: Color(0xFF7C5CFF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'v${m.version}  ·  ${m.catalogs.length} catalog${m.catalogs.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.38),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: addon.enabled,
                onChanged: onToggle,
                activeColor: const Color(0xFF7C5CFF),
              ),
            ],
          ),

          // ── Description ──
          if (m.description != null && m.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              m.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.42),
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Type badges + Remove ──
          Row(
            children: [
              ...m.types.map(
                (type) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.48),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: Colors.red.withValues(alpha: 0.55),
                onPressed: onRemove,
                tooltip: 'Remove addon',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Addon Button
// ─────────────────────────────────────────────────────────────────────────────

class _AddAddonButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _AddAddonButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.18),
          ),
          color: const Color(0xFF7C5CFF).withValues(alpha: 0.04),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF7C5CFF),
                ),
              )
            else
              const Icon(Icons.add_rounded, color: Color(0xFF7C5CFF), size: 24),
            const SizedBox(width: 10),
            Text(
              isLoading ? 'Installing...' : 'Add Metadata Addon',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7C5CFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
