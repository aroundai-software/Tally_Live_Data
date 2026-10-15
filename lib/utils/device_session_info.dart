import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Client-generated session id for single-device login enforcement.
String newDeviceSessionId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String currentDevicePlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'other';
  }
}

/// Generic fallback when device info is unavailable.
String currentDeviceLabel() {
  if (kIsWeb) return 'Web browser';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android device';
    case TargetPlatform.iOS:
      return 'iPhone/iPad';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.macOS:
      return 'Mac';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.fuchsia:
      return 'Device';
  }
}

/// Real device / browser name for session history (e.g. "Pixel 7", "Chrome").
Future<String> resolveDeviceLabel() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) {
      final web = await plugin.webBrowserInfo;
      final browser = (web.browserName.name).trim();
      if (browser.isNotEmpty && browser.toLowerCase() != 'unknown') {
        final pretty = browser[0].toUpperCase() + browser.substring(1);
        final platform = (web.platform ?? '').trim();
        if (platform.isNotEmpty) return '$pretty ($platform)';
        return pretty;
      }
      final ua = (web.userAgent ?? '').toLowerCase();
      if (ua.contains('edg/')) return 'Edge';
      if (ua.contains('chrome/')) return 'Chrome';
      if (ua.contains('firefox/')) return 'Firefox';
      if (ua.contains('safari/') && !ua.contains('chrome')) return 'Safari';
      return 'Web browser';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final a = await plugin.androidInfo;
        final brand = a.brand.trim();
        final model = a.model.trim();
        if (model.isNotEmpty) {
          if (brand.isNotEmpty &&
              !model.toLowerCase().startsWith(brand.toLowerCase())) {
            return '$brand $model';
          }
          return model;
        }
        if (brand.isNotEmpty) return brand;
        return 'Android device';
      case TargetPlatform.iOS:
        final i = await plugin.iosInfo;
        final name = i.name.trim();
        if (name.isNotEmpty) return name;
        final model = i.model.trim();
        if (model.isNotEmpty) return model;
        return 'iPhone/iPad';
      case TargetPlatform.windows:
        final w = await plugin.windowsInfo;
        final name = w.computerName.trim();
        if (name.isNotEmpty) return name;
        return 'Windows';
      case TargetPlatform.macOS:
        final m = await plugin.macOsInfo;
        final name = m.computerName.trim();
        if (name.isNotEmpty) return name;
        final model = m.model.trim();
        if (model.isNotEmpty) return model;
        return 'Mac';
      case TargetPlatform.linux:
        final l = await plugin.linuxInfo;
        final pretty = l.prettyName.trim();
        if (pretty.isNotEmpty) return pretty;
        final name = l.name.trim();
        if (name.isNotEmpty) return name;
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Device';
    }
  } catch (_) {
    return currentDeviceLabel();
  }
}

/// Profile display: "Pixel 7 · 15 Oct, 2:30 PM" or "Not available".
String formatDeviceSessionLine({
  String? label,
  String? platform,
  DateTime? claimedAt,
}) {
  final name = (label != null && label.trim().isNotEmpty)
      ? label.trim()
      : _labelForPlatform(platform);
  if (name == null || name.isEmpty) return 'Not available';
  if (claimedAt == null) return name;
  return '$name · ${_formatClaimedAt(claimedAt)}';
}

String? _labelForPlatform(String? platform) {
  switch ((platform ?? '').toLowerCase()) {
    case 'web':
      return 'Web browser';
    case 'android':
      return 'Android device';
    case 'ios':
      return 'iPhone/iPad';
    case 'windows':
      return 'Windows';
    case 'macos':
      return 'Mac';
    case 'linux':
      return 'Linux';
    case '':
      return null;
    default:
      return 'Device';
  }
}

String _formatClaimedAt(DateTime at) {
  final local = at.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h24 = local.hour;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 >= 12 ? 'PM' : 'AM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]}, $h12:$min $ampm';
}
