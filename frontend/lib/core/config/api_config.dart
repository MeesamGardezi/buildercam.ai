// Purpose: Centralizes runtime config for the BuilderCam transcription module.
import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  // Set GEMINI_API_KEY at build time:
  //   flutter run --dart-define=GEMINI_API_KEY=your_key_here
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-pro',
  );

  static const String demoProjectId = String.fromEnvironment(
    'BUILDERCAM_DEMO_PROJECT_ID',
    defaultValue: 'demo-project-001',
  );
  static const String demoUserId = String.fromEnvironment(
    'BUILDERCAM_DEMO_UID',
    defaultValue: 'project-manager-demo',
  );
  static const String _sowProxyBaseUrlOverride = String.fromEnvironment(
    'BUILDERCAM_SOW_PROXY_BASE_URL',
    defaultValue: '',
  );

  // --- API Base URL ---
  // Comment out one of the two lines below to switch between environments:
  // static const String _baseUrl = 'https://api.buildercam.ai'; // Production
  static const String _baseUrl = 'http://localhost:3001'; // Local

  static String get sowProxyBaseUrl {
    if (_sowProxyBaseUrlOverride.isNotEmpty) {
      return _sowProxyBaseUrlOverride;
    }

    if (kIsWeb) {
      return _baseUrl;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // For local dev on Android emulator, use: 'http://10.0.2.2:3001'
      return _baseUrl;
    }

    return _baseUrl;
  }

  static const String defaultProjectStatus = 'planning';

  static const String apiProjectName = String.fromEnvironment(
    'BUILDERCAM_API_PROJECT_NAME',
    defaultValue: 'BuilderCam',
  );

  static bool get isGeminiConfigured => geminiApiKey.isNotEmpty;

  // ─── Store / update config ────────────────────────────────────────────────
  static const String androidPackageName = 'ai.buildercam';
  static const String iosBundleId = 'ai.buildercam';

  /// Fill in after App Store submission.
  static const String iosAppStoreId = '';
}
