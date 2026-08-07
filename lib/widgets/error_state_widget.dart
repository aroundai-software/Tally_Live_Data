import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class ErrorStateWidget extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  final String? customTitle;
  final String? customMessage;

  const ErrorStateWidget({
    super.key,
    required this.error,
    required this.onRetry,
    this.customTitle,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final errStr = error?.toString().toLowerCase() ?? '';

    bool isNetwork = errStr.contains('socketexception') ||
        errStr.contains('failed host lookup') ||
        errStr.contains('network') ||
        errStr.contains('clientexception') ||
        errStr.contains('connection refused') ||
        errStr.contains('timeout');

    bool isServicePaused = errStr.contains('503') ||
        errStr.contains('service unavailable') ||
        errStr.contains('paused') ||
        errStr.contains('maintenance');

    IconData iconData = Icons.error_outline_rounded;
    String title = customTitle ?? 'Unable to Load Data';
    String message = customMessage ?? 'An unexpected error occurred while loading data.';

    if (isNetwork) {
      iconData = Icons.wifi_off_rounded;
      title = 'No Internet Connection';
      message = 'Please check your mobile data or Wi-Fi settings and try again.';
    } else if (isServicePaused) {
      iconData = Icons.cloud_off_rounded;
      title = 'Service Temporarily Offline';
      message = 'The database service is currently undergoing maintenance or paused. Please try again shortly.';
    } else if (error != null) {
      final cleanMsg = error.toString().replaceAll('Exception:', '').trim();
      if (cleanMsg.isNotEmpty && cleanMsg.length < 120) {
        message = cleanMsg;
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                size: 48,
                color: AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1F36),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
