// Purpose: Boots the BuilderCam shell and wires GoRouter into MaterialApp.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:buildercam/core/core.dart';
import 'package:buildercam/core/services/app_update_service.dart';
import 'package:buildercam/features/auth/auth_module.dart';
import 'package:buildercam/features/credits/credits_module.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

import 'app_updater.dart' deferred as app_updater;
import 'core/firebase_options.dart';
import 'core/router/app_router.dart';
// Deferred PDF editor libraries — split out of the initial bundle but
// prefetched in the background right after launch (see _loadDeferredModules)
// so navigating to the editor is instant. Imported only for `loadLibrary`,
// hence the ignores.
// ignore: unused_import
import 'package:buildercam/features/pdf_editor/pdf_editor_widget.dart'
    deferred as pdf_editor;
// ignore: unused_import
import 'package:buildercam/features/pdf_editor/views/template_preview_page.dart'
    deferred as template_preview;

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Initialize App Update Service (Android Play Core; iOS handled in widget)
  await AppUpdateService.instance.initialize();
  runApp(const BuilderCamApp());
}

class BuilderCamApp extends StatelessWidget {
  const BuilderCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthController>(
      create: (_) => AuthController(AuthService())..init(),
      child: Builder(
        builder: (ctx) {
          final auth = ctx.read<AuthController>();
          return ChangeNotifierProvider<CreditsController>(
            create: (_) => CreditsController(
              CreditsService(),
              auth.getIdToken,
            ),
            child: const _RouterHost(),
          );
        },
      ),
    );
  }
}

/// Builds the GoRouter once and keeps it alive for the lifetime of the app.
/// The router uses [AuthController] as its `refreshListenable`, so it
/// re-evaluates redirects whenever auth state changes.
class _RouterHost extends StatefulWidget {
  const _RouterHost();

  @override
  State<_RouterHost> createState() => _RouterHostState();
}

class _RouterHostState extends State<_RouterHost> with WidgetsBindingObserver {
  late final _router = buildAppRouter(context.read<AuthController>());
  bool _appUpdaterLoaded = false;

  // Handles `buildercam://` deep links — used by Paddle checkout to bring the
  // user back into the app on the billing screen after paying.
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDeferredModules();
    _initDeepLinks();
  }

  // Deep links are mobile-only; the web build returns via a normal URL.
  Future<void> _initDeepLinks() async {
    if (kIsWeb) return;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);
    } catch (_) {
      // No initial link / unsupported platform — ignore.
    }
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {},
    );
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'buildercam') return;
    // buildercam://billing?paid=1 → host is "billing".
    if (uri.host == 'billing' || uri.path.contains('billing')) {
      _router.go('/billing?paid=1');
    }
  }

  Future<void> _loadDeferredModules() async {
    await app_updater.loadLibrary();
    if (mounted) setState(() => _appUpdaterLoaded = true);
    // Warm the PDF editor chunks in the background so they're already cached
    // by the time the user opens the editor. Failures are non-fatal  — the
    // DeferredLoader at each call site will retry the download on demand.
    unawaited(pdf_editor.loadLibrary().catchError((_) {}));
    unawaited(template_preview.loadLibrary().catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppUpdateService.instance.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BuilderCam',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
      builder: (context, child) {
        final body = child ?? const SizedBox.shrink();
        if (_appUpdaterLoaded) {
          return app_updater.AppUpdateChecker(child: body);
        }
        return body;
      },
    );
  }
}
