// Purpose: Cross-platform helpers for detecting the runtime web environment.
// Resolves to a no-op implementation on native platforms and to a
// user-agent-based check on the web.
export 'web_platform_io.dart'
    if (dart.library.js_interop) 'web_platform_web.dart';
