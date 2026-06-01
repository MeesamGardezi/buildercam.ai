// Purpose: Web implementation of the web platform helpers. Uses the browser
// user-agent string to detect mobile web browsers.
import 'package:web/web.dart' as web;

/// Whether the app is running inside a mobile web browser (phone or tablet).
bool get isMobileWeb {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('android') ||
      ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod') ||
      ua.contains('mobile') ||
      // iPadOS 13+ reports a desktop UA but exposes touch points.
      (ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1);
}
