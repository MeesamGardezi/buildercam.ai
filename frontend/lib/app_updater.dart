// This file is intentionally loaded as a DEFERRED library so it is not
// bundled in the first paint frame.
//
// Usage in main.dart:
//   import 'app_updater.dart' deferred as app_updater;
//
//   // Load in initState, then rebuild to inject the wrapper:
//   await app_updater.loadLibrary();
//   setState(() => _appUpdaterLoaded = true);
//
//   // In the MaterialApp builder:
//   if (_appUpdaterLoaded) return app_updater.AppUpdateChecker(child: body);
//   return body;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/config/api_config.dart';

/// Transparent widget that wraps the entire app and silently checks for
/// store updates on launch (and every [_checkInterval] thereafter).
///
/// - **iOS** — queries the iTunes Lookup API with the bundle ID defined in
///   [ApiConfig.iosBundleId] and shows a dialog when a newer version exists.
/// - **Android** — handled natively by [AppUpdateService] via `in_app_update`;
///   this widget is a no-op on Android.
/// - **Web** — always a no-op.
class AppUpdateChecker extends StatefulWidget {
  const AppUpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateChecker> createState() => _AppUpdateCheckerState();
}

class _AppUpdateCheckerState extends State<AppUpdateChecker> {
  static const Duration _checkInterval = Duration(hours: 12);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
    _timer = Timer.periodic(_checkInterval, (_) => _checkForUpdates());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Update check
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkForUpdates() async {
    if (kIsWeb) return;
    // Android updates are handled natively via AppUpdateService.
    if (!kIsWeb && Platform.isAndroid) return;
    try {
      final current = await _getCurrentVersion();
      final latest = await _getStoreVersion();
      if (latest != null && _isNewerVersion(current, latest)) {
        if (mounted) _showUpdateDialog(current, latest);
      }
    } catch (e) {
      debugPrint('[AppUpdateChecker] Update check failed: $e');
    }
  }

  Future<String> _getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version; // e.g. "1.2.3"
  }

  Future<String?> _getStoreVersion() async {
    if (!kIsWeb && Platform.isIOS) {
      final uri = Uri.parse(
        'https://itunes.apple.com/lookup?bundleId=${ApiConfig.iosBundleId}',
      );
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          return results[0]['version'] as String?;
        }
      }
    }
    return null;
  }

  /// Returns `true` if [latest] is strictly newer than [current].
  /// Compares major, minor, and patch segments numerically.
  bool _isNewerVersion(String current, String latest) {
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final cv = i < c.length ? c[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialog
  // ─────────────────────────────────────────────────────────────────────────

  /// Set to `true` to make the dialog non-dismissible (forced update).
  static const bool _forceUpdate = false;

  void _showUpdateDialog(String current, String latest) {
    showDialog<void>(
      context: context,
      barrierDismissible: !_forceUpdate,
      builder: (ctx) => PopScope(
        canPop: !_forceUpdate,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          title: const Text('Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A new version of BuilderCam is available.'),
              const SizedBox(height: 16),
              Row(
                children: [
                  _VersionBadge(label: current, color: Colors.grey),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16),
                  ),
                  _VersionBadge(label: latest, color: Colors.blue),
                ],
              ),
            ],
          ),
          actions: [
            if (!_forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Later'),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _launchStoreUrl();
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchStoreUrl() async {
    Uri? uri;
    if (!kIsWeb && Platform.isIOS) {
      final storeId = ApiConfig.iosAppStoreId;
      if (storeId.isNotEmpty) {
        uri = Uri.parse('https://apps.apple.com/app/id$storeId');
      }
    } else if (!kIsWeb && Platform.isAndroid) {
      uri = Uri.parse(
        'market://details?id=${ApiConfig.androidPackageName}',
      );
    }
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build — transparent pass-through
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widget
// ─────────────────────────────────────────────────────────────────────────────

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
