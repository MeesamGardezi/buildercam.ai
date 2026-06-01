// Purpose: Centralised GoRouter configuration.
//
// Shell routes (/home, /project/:id, /project/:id/sow/:sowId,
// /project/:id/sow/:sowId/pdf, /project/:id/pdf/:pdfDocId) all share
// _kSowHomeKey so GoRouter reuses the same SowHomeScreen widget instance.
// SowHomeScreen.didUpdateWidget reacts to prop changes to swap the
// main-panel content without rebuilding the sidebar.
//
// URL conventions:
//   /project/:projectId                    – project workspace (sidebar visible)
//   /project/:projectId/sow/:sowId         – SOW document (sidebar visible)
//   /project/:projectId/sow/:sowId/pdf     – SOW-linked PDF editor (sidebar visible)
//   /project/:projectId/pdf/:pdfDocId      – standalone PDF document (sidebar visible)
//   /project/:projectId/recording          – fullscreen recording
//   /project/:projectId/video-feed         – fullscreen video feed
//   Path params  → mandatory IDs that survive a browser refresh
//   Extra params → in-memory fast-path data (lost on refresh; screens
//                  lazy-load from the backend as fallback)

import 'package:buildercam/core/core.dart';
import 'package:buildercam/features/auth/auth_module.dart';
import 'package:buildercam/features/auth/views/screens/legal_screen.dart';
import 'package:buildercam/features/credits/credits_module.dart';
import 'package:buildercam/features/pdf_editor/models/pdf_document_data.dart';
import 'package:buildercam/features/pdf_editor/models/template_model.dart';
import 'package:buildercam/features/pdf_editor/views/template_preview_page.dart'
    deferred as template_preview;
import 'package:buildercam/features/sow_transcription/sow_transcription_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../guest_home_screen.dart';

// ── Route registry ────────────────────────────────────────────────────────────

enum AppRoute {
  splash('/splash', 'splash'),
  login('/login', 'login'),
  register('/register', 'register'),
  setupCompany('/setup-company', 'setup-company'),
  // ── Guest ──────────────────────────────────────────────────────────────────
  guest('/guest', 'guest'),
  guestRecording('/guest/recording/:projectId', 'guest-recording'),
  guestVideoFeed('/guest/video-feed/:projectId', 'guest-video-feed'),
  // ── Shell routes (sidebar always visible) ─────────────────────────────────
  home('/home', 'home'),
  project('/project/:projectId', 'project'),
  sowDocument('/project/:projectId/sow/:sowId', 'sow-document'),
  pdfEditor('/project/:projectId/sow/:sowId/pdf', 'pdf-editor'),
  pdfDocument('/project/:projectId/pdf/:pdfDocId', 'pdf-document'),
  // ── Fullscreen (no sidebar) ────────────────────────────────────────────────
  recording('/project/:projectId/recording', 'recording'),
  videoFeed('/project/:projectId/video-feed', 'video-feed'),
  sowHistory('/project/:projectId/recording/history', 'sow-history'),
  templatePreview('/template/preview', 'template-preview'),
  // ── Settings / team (pushed on top) ───────────────────────────────────────
  sowSettings('/home/settings', 'sow-settings'),
  companySettings('/company/settings', 'company-settings'),
  teamInvite('/team/invite', 'team-invite'),
  teamSettings('/team/settings', 'team-settings'),
  activityLog('/activity', 'activity-log'),
  billing('/billing', 'billing'),
  privacy('/privacy', 'privacy'),
  terms('/terms', 'terms'),
  // ── Standalone template viewer (no shell) ─────────────────────────────────
  sowTemplate('/sow/template', 'sow-template');

  const AppRoute(this.path, this.name);
  final String path;
  final String name;
}

// Page key shared by all shell routes so GoRouter reuses one SowHomeScreen.
const _kSowHomeKey = ValueKey<String>('sow-home');

// ── Router factory ────────────────────────────────────────────────────────────

GoRouter buildAppRouter(AuthController auth) {
  return GoRouter(
    initialLocation: AppRoute.splash.path,
    debugLogDiagnostics: false,
    refreshListenable: auth,
    redirect: (context, state) => _redirect(auth, state),
    errorBuilder: (context, state) => _NotFoundScreen(error: state.error),
    routes: [
      // ── Auth ─────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoute.splash.path,
        name: AppRoute.splash.name,
        builder: (_, __) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoute.login.path,
        name: AppRoute.login.name,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.register.path,
        name: AppRoute.register.name,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoute.setupCompany.path,
        name: AppRoute.setupCompany.name,
        builder: (_, __) => const SetupCompanyScreen(),
      ),

      // ── Guest ─────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoute.guest.path,
        name: AppRoute.guest.name,
        builder: (_, __) => const GuestHomeScreen(),
      ),
      GoRoute(
        path: AppRoute.guestRecording.path,
        name: AppRoute.guestRecording.name,
        builder: (context, state) {
          final args = state.extra as SowRecordingArgs?;
          final projectId = args?.projectId ??
              state.pathParameters['projectId'] ??
              ApiConfig.demoProjectId;
          return SowRecordingScreen(
            projectId: projectId,
            createdBy: args?.createdBy ?? 'guest',
            tokenProvider: auth.getIdToken,
          );
        },
      ),
      GoRoute(
        path: AppRoute.guestVideoFeed.path,
        name: AppRoute.guestVideoFeed.name,
        builder: (context, state) {
          final args = state.extra as VideoFeedArgs?;
          final projectId = args?.projectId ??
              state.pathParameters['projectId'] ??
              ApiConfig.demoProjectId;
          return VideoFeedScreen(
            projectId: projectId,
            onFeedComplete: args?.onFeedComplete,
          );
        },
      ),

      // ── Shell routes ──────────────────────────────────────────────────────
      // All four routes share _kSowHomeKey so GoRouter reuses the same
      // SowHomeScreen instance.  didUpdateWidget handles prop changes.
      GoRoute(
        path: AppRoute.home.path,
        name: AppRoute.home.name,
        pageBuilder: (_, __) => MaterialPage(
          key: _kSowHomeKey,
          child: SowHomeScreen(tokenProvider: auth.getIdToken),
        ),
      ),
      GoRoute(
        path: AppRoute.project.path,
        name: AppRoute.project.name,
        pageBuilder: (_, state) => MaterialPage(
          key: _kSowHomeKey,
          child: SowHomeScreen(
            tokenProvider: auth.getIdToken,
            initialProjectId: state.pathParameters['projectId'],
            initialTab: state.uri.queryParameters['tab'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoute.sowDocument.path,
        name: AppRoute.sowDocument.name,
        pageBuilder: (_, state) => MaterialPage(
          key: _kSowHomeKey,
          child: SowHomeScreen(
            tokenProvider: auth.getIdToken,
            initialProjectId: state.pathParameters['projectId'],
            initialSowId: state.pathParameters['sowId'],
            sowDocumentArgs: state.extra as SowDocumentArgs?,
          ),
        ),
      ),
      GoRoute(
        path: AppRoute.pdfEditor.path,
        name: AppRoute.pdfEditor.name,
        pageBuilder: (_, state) => MaterialPage(
          key: _kSowHomeKey,
          child: SowHomeScreen(
            tokenProvider: auth.getIdToken,
            initialProjectId: state.pathParameters['projectId'],
            initialSowId: state.pathParameters['sowId'],
            showPdfEditor: true,
            pdfEditorArgs: state.extra as PdfEditorArgs?,
          ),
        ),
      ),
      GoRoute(
        path: AppRoute.pdfDocument.path,
        name: AppRoute.pdfDocument.name,
        pageBuilder: (_, state) => MaterialPage(
          key: _kSowHomeKey,
          child: SowHomeScreen(
            tokenProvider: auth.getIdToken,
            initialProjectId: state.pathParameters['projectId'],
            initialPdfDocId: state.pathParameters['pdfDocId'],
          ),
        ),
      ),

      // ── Fullscreen routes (no sidebar) ────────────────────────────────────
      GoRoute(
        path: AppRoute.recording.path,
        name: AppRoute.recording.name,
        builder: (context, state) {
          final args = state.extra as SowRecordingArgs?;
          final projectId = args?.projectId ??
              state.pathParameters['projectId'] ??
              ApiConfig.demoProjectId;
          return SowRecordingScreen(
            projectId: projectId,
            createdBy: args?.createdBy ?? auth.user?.uid ?? 'guest',
            tokenProvider: auth.getIdToken,
          );
        },
      ),
      GoRoute(
        path: AppRoute.videoFeed.path,
        name: AppRoute.videoFeed.name,
        builder: (context, state) {
          final args = state.extra as VideoFeedArgs?;
          final projectId = args?.projectId ??
              state.pathParameters['projectId'] ??
              ApiConfig.demoProjectId;
          return VideoFeedScreen(
            projectId: projectId,
            onFeedComplete: args?.onFeedComplete,
          );
        },
      ),

      // ── SOW recording history (fullscreen push) ──────────────────────────
      GoRoute(
        path: AppRoute.sowHistory.path,
        name: AppRoute.sowHistory.name,
        builder: (context, state) {
          final args = state.extra as SowHistoryArgs?;
          final projectId = state.pathParameters['projectId']!;
          final history = SowHistoryScreen(projectId: projectId);
          final controller = args?.controller;
          if (controller == null) return history;
          return ChangeNotifierProvider<SowRecordingController>.value(
            value: controller,
            child: history,
          );
        },
      ),

      // ── PDF template preview (fullscreen push) ───────────────────────────
      GoRoute(
        path: AppRoute.templatePreview.path,
        name: AppRoute.templatePreview.name,
        builder: (context, state) {
          final args = state.extra as TemplatePreviewArgs?;
          if (args == null) {
            return const _NotFoundScreen();
          }
          return DeferredLoader(
            loadLibrary: template_preview.loadLibrary,
            builder: (context) => template_preview.TemplatePreviewPage(
              template: args.template,
              // exportService is stored as Object to keep the heavy
              // PdfExportService type out of the initial bundle; cast via
              // dynamic so it binds to the deferred parameter type.
              exportService: args.exportService as dynamic,
              canExport: args.canExport,
            ),
          );
        },
      ),

      // ── Standalone template viewer (fullscreen push, no shell) ────────────
      GoRoute(
        path: AppRoute.sowTemplate.path,
        name: AppRoute.sowTemplate.name,
        builder: (context, state) {
          final args = state.extra as SowDocumentArgs?;
          return SowDocumentScreen(
            projectName: args?.projectName ?? '',
            initialContent: args?.initialContent ?? '',
            clientName: args?.clientName ?? '',
            siteLocation: args?.siteLocation ?? '',
            scopeSummary: args?.scopeSummary ?? '',
            transcriptIds: args?.transcriptIds ?? const [],
            frameUrls: args?.frameUrls ?? const [],
            backendService: args?.backendService,
            onBack: () => context.pop(),
          );
        },
      ),

      GoRoute(
        path: AppRoute.sowSettings.path,
        name: AppRoute.sowSettings.name,
        builder: (_, __) => const SowSettingsScreen(),
      ),

      // ── Account / team ─────────────────────────────────────────────────────
      GoRoute(
        path: AppRoute.companySettings.path,
        name: AppRoute.companySettings.name,
        builder: (_, __) => const CompanySettingsScreen(),
      ),
      GoRoute(
        path: AppRoute.teamInvite.path,
        name: AppRoute.teamInvite.name,
        builder: (_, __) => const InviteMemberScreen(),
      ),
      GoRoute(
        path: AppRoute.teamSettings.path,
        name: AppRoute.teamSettings.name,
        builder: (_, __) => const TeamSettingsScreen(),
      ),
      GoRoute(
        path: AppRoute.activityLog.path,
        name: AppRoute.activityLog.name,
        builder: (_, __) => const ActivityLogScreen(),
      ),
      GoRoute(
        path: AppRoute.billing.path,
        name: AppRoute.billing.name,
        builder: (_, __) => const BillingScreen(),
      ),
      GoRoute(
        path: AppRoute.privacy.path,
        name: AppRoute.privacy.name,
        builder: (_, __) => const LegalScreen(document: LegalDocument.privacy),
      ),
      GoRoute(
        path: AppRoute.terms.path,
        name: AppRoute.terms.name,
        builder: (_, __) => const LegalScreen(document: LegalDocument.terms),
      ),
    ],  
  );
}

// ── Redirect logic ────────────────────────────────────────────────────────────

// Stores the URL the user originally requested while auth was still resolving.
// This lets us restore the correct page after a hard refresh on any deep link.
String? _pendingDeepLink;

String? _redirect(AuthController auth, GoRouterState state) {
  final loc = state.uri.path;
  final query = state.uri.query;
  final fullLoc = query.isEmpty ? loc : '$loc?$query';

  // Legal pages are always accessible — no auth required.
  if (loc == AppRoute.privacy.path || loc == AppRoute.terms.path) return null;

  // Auth still resolving → hold on splash; remember where we were headed.
  if (auth.status == AuthStatus.unknown) {
    if (loc != AppRoute.splash.path) {
      // Only save the first non-splash URL — don't overwrite it on subsequent calls.
      _pendingDeepLink ??= fullLoc;
      return AppRoute.splash.path;
    }
    return null;
  }

  final atSplash = loc == AppRoute.splash.path;
  final atAuthScreen =
      loc == AppRoute.login.path || loc == AppRoute.register.path;

  switch (auth.status) {
    case AuthStatus.unauthenticated:
      // Clear any pending deep link when the user is signed out.
      _pendingDeepLink = null;
      if (atAuthScreen) return null;
      return AppRoute.login.path;

    case AuthStatus.noCompany:
      if (loc == AppRoute.setupCompany.path) return null;
      return AppRoute.setupCompany.path;

    case AuthStatus.authenticated:
      final isGuest = auth.user?.isGuest == true;
      final isOwner = auth.user?.isOwner == true;
      final home = isGuest ? AppRoute.guest.path : AppRoute.home.path;

      // Bounce away from auth / splash / setup once signed in.
      if (atAuthScreen || atSplash || loc == AppRoute.setupCompany.path) {
        // Restore the original deep-link if it is valid for this user.
        final deep = _pendingDeepLink;
        _pendingDeepLink = null;
        if (deep != null &&
            _isValidDeepLink(deep.split('?').first, isGuest, isOwner)) {
          return deep;
        }
        return home;
      }

      // Guests are confined to /guest/** paths.
      if (isGuest && (loc.startsWith('/home') || loc.startsWith('/project'))) {
        return AppRoute.guest.path;
      }
      // Non-guests are confined to /home/** /project/** and team/activity paths.
      if (!isGuest && loc.startsWith('/guest')) {
        return AppRoute.home.path;
      }

      // Owner-only screens — redirect members and guests away.
      if (!isOwner &&
          (loc == AppRoute.teamInvite.path ||
              loc == AppRoute.teamSettings.path)) {
        return AppRoute.home.path;
      }

      return null;

    case AuthStatus.unknown:
      return null;
  }
}

/// Returns true when [path] is a URL the given user is allowed to deep-link to.
bool _isValidDeepLink(String path, bool isGuest, bool isOwner) {
  if (isGuest) return path.startsWith('/guest');
  if (!isOwner &&
      (path == AppRoute.teamInvite.path ||
          path == AppRoute.teamSettings.path)) {
    return false;
  }
  return path.startsWith('/home') ||
      path.startsWith('/project') ||
      path.startsWith('/team') ||
      path.startsWith('/template') ||
      path == AppRoute.activityLog.path ||
      path == AppRoute.billing.path;
}

// ── Typed argument bundles ────────────────────────────────────────────────────
//
// Pass rich runtime data through `extra:` on every `context.pushNamed` call.
// These are NOT URL-serialised — treat them as a fast-path cache only.

class SowRecordingArgs {
  const SowRecordingArgs({required this.projectId, required this.createdBy});
  final String projectId;
  final String createdBy;
}

class VideoFeedArgs {
  const VideoFeedArgs({required this.projectId, this.onFeedComplete});
  final String projectId;
  final void Function(List<CapturedFrame> frames, String transcript)?
      onFeedComplete;
}

class SowDocumentArgs {
  const SowDocumentArgs({
    required this.projectName,
    required this.initialContent,
    this.clientName = '',
    this.siteLocation = '',
    this.scopeSummary = '',
    this.projectId,
    this.documentId,
    this.transcriptIds = const [],
    this.frameUrls = const [],
    this.backendService,
  });
  final String projectName;
  final String initialContent;
  final String clientName;
  final String siteLocation;
  final String scopeSummary;
  final String? projectId;
  final String? documentId;
  final List<String> transcriptIds;
  final List<String> frameUrls;
  final SowBackendService? backendService;
}

class PdfEditorArgs {
  const PdfEditorArgs({
    required this.initialData,
    required this.apiBaseUrl,
    this.companyId = '',
    this.projectId,
    this.frameUrls = const [],
    this.tokenProvider,
  });
  final PdfDocumentData initialData;
  final String apiBaseUrl;
  final String companyId;
  final String? projectId;
  final List<String> frameUrls;
  final Future<String?> Function()? tokenProvider;
}

class SowHistoryArgs {
  const SowHistoryArgs({required this.controller});
  final SowRecordingController controller;
}

class TemplatePreviewArgs {
  const TemplatePreviewArgs({
    required this.template,
    required this.exportService,
    this.canExport = true,
  });
  final TemplateModel template;
  /// Stored as [Object] (concretely a `PdfExportService`) so the heavy PDF
  /// export code stays out of the initial bundle. The template-preview route
  /// casts it back when it lazily loads the editor library.
  final Object exportService;
  final bool canExport;
}

// ── Helper screens ────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Image.asset(
            'assets/logos/buildercam-icon-256-transparent.png',
            width: 96,
            height: 96,
          ),
        ),
      );
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({this.error});
  final Exception? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Page not found')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.help_outline_rounded, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'The page you requested does not exist.',
                  textAlign: TextAlign.center,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(AppRoute.home.path),
                  child: const Text('Go home'),
                ),
              ],
            ),
          ),
        ),
      );
}
