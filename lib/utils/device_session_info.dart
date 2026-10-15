import 'dart:math';

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

/// Stored for support; not shown on the force-login popup.
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
