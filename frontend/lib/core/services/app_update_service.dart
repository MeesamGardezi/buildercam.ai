import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:in_app_update/in_app_update.dart';

/// Centralized App Update Service
///
/// Handles forced & flexible updates for Android via the Play Core API.
///
/// **Android** – Uses the Play Core In-App Updates API via [InAppUpdate].
///   • Checks for updates on every app resume.
///   • If the update priority is high (≥ 4) → immediate (forced) update.
///   • Otherwise → flexible update (downloads in background, installs on next restart).
///
/// **iOS** – Handled declaratively by [AppUpdateChecker] (deferred library),
///   which checks the iTunes Lookup API and shows a custom update dialog.
///
/// **Web** – No-op. Web apps are updated on deploy automatically.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// Whether we've already started monitoring. Prevents double-init.
  bool _initialized = false;

  // ─── Android state ──────────────────────────────────────────────────────────
  AppUpdateInfo? _androidUpdateInfo;

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Call once from [main] after Firebase is initialized.
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    if (!kIsWeb && Platform.isAndroid) {
      await _checkAndroidUpdate();
    }
    // iOS checking is handled declaratively via the AppUpdateChecker widget.
  }

  /// Checks for an Android in-app update and starts it if available.
  /// Called on init and retriggered on [AppLifecycleState.resumed].
  Future<void> _checkAndroidUpdate() async {
    try {
      _androidUpdateInfo = await InAppUpdate.checkForUpdate();

      if (_androidUpdateInfo?.updateAvailability ==
          UpdateAvailability.updateAvailable) {
        final priority = _androidUpdateInfo?.updatePriority ?? 0;

        if (priority >= 4) {
          // High-priority / critical update → force immediate update.
          debugPrint('[AppUpdateService] Performing IMMEDIATE Android update');
          await InAppUpdate.performImmediateUpdate();
        } else if (_androidUpdateInfo!.flexibleUpdateAllowed) {
          // Non-critical update → download in background.
          debugPrint('[AppUpdateService] Starting FLEXIBLE Android update');
          await InAppUpdate.startFlexibleUpdate();
          // Auto-complete once downloaded.
          await InAppUpdate.completeFlexibleUpdate();
        }
      } else {
        debugPrint('[AppUpdateService] No Android update available');
      }
    } catch (e) {
      // Play Core throws on emulators / debug builds / sideloaded APKs.
      // Swallow gracefully – never block app startup.
      debugPrint('[AppUpdateService] Android update check failed: $e');
    }
  }

  /// Re-check for updates. Call on [AppLifecycleState.resumed].
  Future<void> onAppResumed() async {
    if (kIsWeb) return;
    if (!kIsWeb && Platform.isAndroid) {
      await _checkAndroidUpdate();
    }
  }
}
