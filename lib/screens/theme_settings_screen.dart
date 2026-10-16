import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/theme_provider.dart';

/// Pick Light / Dark / System default.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([controller, AppTheme.revision]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: AppTheme.surfaceColor,
          appBar: AppBar(
            title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.cardColor,
            elevation: 0,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Choose how TallyLive looks on this device.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      _option(
                        controller: controller,
                        mode: ThemeMode.system,
                        title: 'System default',
                        subtitle: 'Match your phone’s light or dark setting',
                        icon: Icons.brightness_auto_rounded,
                        selected: controller.mode == ThemeMode.system,
                        scheme: scheme,
                        showDivider: true,
                      ),
                      _option(
                        controller: controller,
                        mode: ThemeMode.light,
                        title: 'Light',
                        subtitle: 'Always use light appearance',
                        icon: Icons.light_mode_rounded,
                        selected: controller.mode == ThemeMode.light,
                        scheme: scheme,
                        showDivider: true,
                      ),
                      _option(
                        controller: controller,
                        mode: ThemeMode.dark,
                        title: 'Dark',
                        subtitle: 'Always use dark appearance',
                        icon: Icons.dark_mode_rounded,
                        selected: controller.mode == ThemeMode.dark,
                        scheme: scheme,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _option({
    required ThemeController controller,
    required ThemeMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required ColorScheme scheme,
    required bool showDivider,
  }) {
    return Column(
      children: [
        ListTile(
          onTap: () => controller.setMode(mode),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: selected
              ? Icon(Icons.check_circle_rounded, color: scheme.primary)
              : Icon(Icons.circle_outlined, color: AppTheme.dividerColor),
        ),
        if (showDivider)
          Divider(height: 1, indent: 68, color: AppTheme.dividerColor),
      ],
    );
  }
}
