import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Shown when a single-company-only report is opened while in Combined mode.
class CombinedModeUnavailable extends StatelessWidget {
  final String featureName;

  const CombinedModeUnavailable({super.key, required this.featureName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          featureName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 16,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                '$featureName is not available in Combined mode',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Switch to a single company to view this report.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
