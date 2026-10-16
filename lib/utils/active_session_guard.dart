import 'dart:async';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../screens/login_screen.dart';
import '../providers/company_provider.dart';

/// Watches [users.active_session_id] (Realtime + periodic poll + RPC errors)
/// and logs out when another device claims the account.
mixin ActiveSessionGuard<T extends StatefulWidget> on State<T> {
  StreamSubscription<Map<String, dynamic>>? _activeSessionSub;
  StreamSubscription<void>? _invalidationSub;
  Timer? _activeSessionPoll;
  bool _sessionKickInProgress = false;

  static const _pollInterval = Duration(seconds: 30);

  void startActiveSessionGuard() {
    final user = SupabaseService().currentUser;
    if (user == null) return;
    stopActiveSessionGuard();

    _activeSessionSub = SupabaseService().streamUserProfile(user.id).listen(
      (profile) {
        if (!mounted || profile.isEmpty || _sessionKickInProgress) return;
        unawaited(_checkActiveSession(profile));
      },
      onError: (_) {},
    );

    _invalidationSub = SupabaseService.deviceSessionInvalidated.stream.listen((_) {
      if (!mounted || _sessionKickInProgress) return;
      unawaited(kickForForeignSession());
    });

    _activeSessionPoll = Timer.periodic(_pollInterval, (_) {
      if (!mounted || _sessionKickInProgress) return;
      unawaited(_pollActiveSession());
    });

    // Immediate check on enter (covers missed Realtime while backgrounded).
    unawaited(_pollActiveSession());
  }

  void stopActiveSessionGuard() {
    _activeSessionSub?.cancel();
    _activeSessionSub = null;
    _invalidationSub?.cancel();
    _invalidationSub = null;
    _activeSessionPoll?.cancel();
    _activeSessionPoll = null;
  }

  Future<void> _pollActiveSession() async {
    final ok = await SupabaseService().isLocalDeviceSessionStillValid();
    if (!ok && mounted) {
      await kickForForeignSession();
    }
  }

  Future<void> _checkActiveSession(Map<String, dynamic> profile) async {
    final remote = profile['active_session_id']?.toString();
    if (remote == null || remote.isEmpty) return;
    final local = await UserPreferencesService.loadActiveSessionId();
    if (local == null || local.isEmpty) return;
    if (remote == local) return;
    await kickForForeignSession();
  }

  Future<void> kickForForeignSession() async {
    if (_sessionKickInProgress || !mounted) return;
    _sessionKickInProgress = true;
    stopActiveSessionGuard();
    try {
      try {
        CompanyProvider.of(context).clearCompany();
        CompanyProvider.of(context).clearUserCapabilities();
      } catch (_) {}
      await UserPreferencesService.markSignedOutByOtherDevice();
      await SupabaseService().signOut();
      await UserPreferencesService.clearActiveSessionId();
      if (!mounted) return;
      // LoginScreen shows the "signed in elsewhere" notice once via prefs.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } finally {
      _sessionKickInProgress = false;
    }
  }
}
