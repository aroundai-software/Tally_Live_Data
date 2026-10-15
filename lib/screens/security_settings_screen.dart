import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/supabase_service.dart';
import '../utils/device_session_info.dart';
import '../widgets/shimmer_loading.dart';

/// Current device + recent login history (up to 5).
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;
  String _currentDeviceLine = 'Not available';
  List<String> _deviceHistoryLines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = _service.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final profile = await _service.getUserProfile(user.id);
      final history = await _service.getDeviceLoginHistory(userId: user.id);
      if (!mounted) return;
      setState(() {
        _currentDeviceLine = formatDeviceSessionLine(
          label: profile?['active_device_label']?.toString(),
          platform: profile?['active_device_platform']?.toString(),
          claimedAt: DateTime.tryParse(
            profile?['session_claimed_at']?.toString() ?? '',
          ),
        );
        _deviceHistoryLines = history
            .map(
              (row) => formatDeviceSessionLine(
                label: row['device_label']?.toString(),
                platform: row['device_platform']?.toString(),
                claimedAt: DateTime.tryParse(
                  row['claimed_at']?.toString() ??
                      row['ended_at']?.toString() ??
                      '',
                ),
              ),
            )
            .where((line) => line != 'Not available')
            .toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: const Text(
          'Devices & Login',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const ShimmerGridLoading(itemCount: 3)
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              'Current device',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1F36),
                              ),
                            ),
                          ),
                          const Divider(height: 1, color: AppTheme.dividerColor),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.devices_rounded,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Logged in now',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              _currentDeviceLine,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1F36),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              'Recent login history',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1F36),
                              ),
                            ),
                          ),
                          const Divider(height: 1, color: AppTheme.dividerColor),
                          if (_deviceHistoryLines.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                              child: Text(
                                'No previous devices yet. History appears after you sign in on another device or sign out.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  height: 1.4,
                                ),
                              ),
                            )
                          else
                            ..._deviceHistoryLines.asMap().entries.map((entry) {
                              final i = entry.key;
                              return Column(
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: AppTheme.primaryColor
                                          .withValues(alpha: 0.1),
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      entry.value,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1F36),
                                      ),
                                    ),
                                  ),
                                  if (i < _deviceHistoryLines.length - 1)
                                    const Divider(
                                      height: 1,
                                      indent: 68,
                                      color: AppTheme.dividerColor,
                                    ),
                                ],
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card({required Widget child}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: child,
      ),
    );
  }
}
