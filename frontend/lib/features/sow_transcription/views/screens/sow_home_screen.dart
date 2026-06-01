// Purpose: Hosts the project dashboard, creation flow, and embedded transcription workspace.
import 'dart:async';

import 'package:buildercam/core/core.dart';
import 'package:buildercam/core/router/app_router.dart';
import 'package:buildercam/features/auth/auth_module.dart';
import 'package:buildercam/features/credits/credits_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/sow_recording_controller.dart';
import '../../models/sow_document_model.dart';
import '../../models/sow_template_model.dart';
import '../../models/sow_transcript_model.dart';
import '../../models/pdf_document_model.dart';
import '../../services/gemini_live_service.dart';
import '../../services/sow_firestore_service.dart';
import '../../services/shared_prefs_service.dart';
import '../../services/video_frame_storage_service.dart';
import 'package:buildercam/features/pdf_editor/models/pdf_document_data.dart';
import 'package:buildercam/features/pdf_editor/pdf_editor_widget.dart'
    deferred as pdf_editor;

import '../widgets/recording_control_button.dart';
import '../widgets/recording_status_bar.dart';
import 'sow_document_screen.dart';

class SowHomeScreen extends StatefulWidget {
  const SowHomeScreen({
    super.key,
    this.tokenProvider,
    this.initialProjectId,
    this.initialTab,
    this.initialSowId,
    this.sowDocumentArgs,
    this.showPdfEditor = false,
    this.pdfEditorArgs,
    this.initialPdfDocId,
  });

  /// Provides the current user's Firebase ID token for authenticated requests.
  final Future<String?> Function()? tokenProvider;

  /// If set, the project with this ID is automatically selected on load.
  final String? initialProjectId;

  /// If set, the mobile workspace opens on this tab ('record' or 'transcripts').
  final String? initialTab;

  /// If set, the SOW document with this ID is embedded in the main panel.
  final String? initialSowId;

  /// Fast-path data for the SOW document (avoids a backend round-trip).
  final SowDocumentArgs? sowDocumentArgs;

  /// When true the PDF editor is shown in the main panel.
  final bool showPdfEditor;

  /// Fast-path data for the PDF editor.
  final PdfEditorArgs? pdfEditorArgs;

  /// If set, the standalone PDF document with this ID is shown in the main panel.
  /// Use 'new' to open a blank editor that creates a new document on save.
  final String? initialPdfDocId;

  @override
  State<SowHomeScreen> createState() => _SowHomeScreenState();
}

class _SowHomeScreenState extends State<SowHomeScreen> {
  late SowBackendService _backendService;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _siteController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _loading = true;
  bool _creatingProject = false;
  String? _errorMessage;
  List<SowProjectModel> _projects = <SowProjectModel>[];
  SowProjectModel? _selectedProject;
  List<SowTranscriptModel> _selectedTranscripts = <SowTranscriptModel>[];

  List<SowTemplateModel> _templates = <SowTemplateModel>[];
  List<Map<String, dynamic>> _pdfTemplates = <Map<String, dynamic>>[];
  bool _templatesLoading = false;

  /// Tracks the active mobile tab ('record' or 'transcripts').
  /// Kept in sync with the URL query param via didUpdateWidget.
  String? _currentTab;

  // ── SOW document embedded state ─────────────────────────────────────────
  String? _currentSowId;
  SowDocumentModel? _currentSowDoc;
  SowDocumentArgs? _currentSowDocArgs;
  bool _sowDocLoading = false;

  // ── PDF editor embedded state ────────────────────────────────────────────
  bool _showPdfEditor = false;
  PdfEditorArgs? _currentPdfArgs;

  /// Tracks the pdf-document id that the SOW-linked PDF editor saves into.
  /// First save in a session creates a new pdf-document; subsequent saves
  /// update it. Reset whenever the editor is closed.
  String? _linkedPdfDocId;
  String? _linkedPdfDocTitle;

  // ── Standalone PDF document state ─────────────────────────────────────────
  String? _currentPdfDocId;
  PdfDocumentModel? _currentPdfDoc;
  bool _pdfDocLoading = false;

  /// Name entered in the "New PDF" dialog before the editor opens.
  /// Used so the first save doesn't re-prompt for a name.
  String? _pendingNewPdfName;

  /// Incremented when returning from a SOW doc so _MainWorkspacePanel
  /// recreates and reloads the saved-SOW list.
  int _workspaceReloadVersion = 0;

  @override
  void initState() {
    super.initState();
    _backendService = SowBackendService(tokenProvider: widget.tokenProvider);
    _currentTab = widget.initialTab;
    _currentSowId = widget.initialSowId;
    _currentSowDocArgs = widget.sowDocumentArgs;
    _showPdfEditor = widget.showPdfEditor;
    _currentPdfArgs = widget.pdfEditorArgs;
    _loadProjects();
    _loadTemplates();
    if (_currentSowId != null &&
        _currentSowDocArgs == null &&
        _currentSowId != 'new') {
      unawaited(_loadSowDocument(_currentSowId!));
    }
    _currentPdfDocId = widget.initialPdfDocId;
    if (_currentPdfDocId != null && _currentPdfDocId != 'new') {
      _pdfDocLoading = true;
      unawaited(_loadPdfDocument(_currentPdfDocId!));
    }
  }

  // Called by GoRouter when the URL changes but the same widget instance is
  // reused (because all shell routes share the 'sow-home' pageKey).
  @override
  void didUpdateWidget(SowHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProjectId != oldWidget.initialProjectId) {
      _handleProjectIdChange(widget.initialProjectId);
    }
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _currentTab = widget.initialTab);
    }

    // SOW document ID changed.
    if (widget.initialSowId != oldWidget.initialSowId) {
      if (widget.initialSowId == null && oldWidget.initialSowId != null) {
        // Returning from SOW doc — reload the workspace panel.
        setState(() {
          _currentSowId = null;
          _currentSowDoc = null;
          _currentSowDocArgs = null;
          _sowDocLoading = false;
          _showPdfEditor = false;
          _currentPdfArgs = null;
          _workspaceReloadVersion++;
        });
      } else {
        final needsLoad = widget.sowDocumentArgs == null &&
            widget.initialSowId != null &&
            widget.initialSowId != 'new';
        setState(() {
          _currentSowId = widget.initialSowId;
          _currentSowDoc = null;
          _currentSowDocArgs = widget.sowDocumentArgs;
          _sowDocLoading = needsLoad;
        });
        if (needsLoad) unawaited(_loadSowDocument(widget.initialSowId!));
      }
    }

    // Fast-path args update.
    if (widget.sowDocumentArgs != oldWidget.sowDocumentArgs &&
        widget.sowDocumentArgs != null) {
      setState(() => _currentSowDocArgs = widget.sowDocumentArgs);
    }

    // PDF editor mode.
    if (widget.showPdfEditor != oldWidget.showPdfEditor) {
      setState(() {
        _showPdfEditor = widget.showPdfEditor;
        if (!widget.showPdfEditor) _currentPdfArgs = null;
      });
    }
    if (widget.pdfEditorArgs != oldWidget.pdfEditorArgs &&
        widget.pdfEditorArgs != null) {
      setState(() => _currentPdfArgs = widget.pdfEditorArgs);
    }

    // Standalone PDF document ID changed.
    if (widget.initialPdfDocId != oldWidget.initialPdfDocId) {
      final newDocId = widget.initialPdfDocId;
      if (newDocId == null) {
        setState(() {
          _currentPdfDocId = null;
          _currentPdfDoc = null;
          _pdfDocLoading = false;
        });
      } else {
        setState(() {
          _currentPdfDocId = newDocId;
          _currentPdfDoc = null;
          _pdfDocLoading = newDocId != 'new';
        });
        if (newDocId != 'new') unawaited(_loadPdfDocument(newDocId));
      }
    }
  }

  /// Reacts to the project ID changing in the URL without a full widget rebuild.
  void _handleProjectIdChange(String? newProjectId) {
    if (newProjectId == null) {
      setState(() {
        _selectedProject = null;
        _selectedTranscripts = [];
        _errorMessage = null;
      });
      return;
    }
    // Prefer finding the project in the already-loaded list to avoid a full reload.
    if (_projects.isNotEmpty) {
      final matches = _projects.where((p) => p.id == newProjectId);
      if (matches.isNotEmpty) {
        setState(() {
          _selectedProject = matches.first;
          _errorMessage = null;
        });
        unawaited(_loadSelectedProject(newProjectId));
        return;
      }
    }
    // Not found locally — do a full reload (e.g., deep-link / direct URL entry).
    unawaited(_loadProjects());
  }

  @override
  void dispose() {
    _backendService.dispose();
    _searchController.dispose();
    _nameController.dispose();
    _clientController.dispose();
    _siteController.dispose();
    _scopeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── SOW / PDF navigation helpers ──────────────────────────────────────────

  Future<void> _loadSowDocument(String sowId) async {
    setState(() => _sowDocLoading = true);
    try {
      final projectId =
          widget.initialProjectId ?? _selectedProject?.id;
      if (projectId == null) {
        if (mounted) setState(() => _sowDocLoading = false);
        return;
      }
      final results = await Future.wait<dynamic>([
        _backendService.getSowDocument(projectId, sowId),
        if (_selectedProject == null) _backendService.fetchProject(projectId),
      ]);
      if (!mounted) return;
      final doc = results[0] as SowDocumentModel?;
      if (_selectedProject == null && results.length > 1) {
        final project = results[1] as SowProjectModel?;
        if (project != null) setState(() => _selectedProject = project);
      }
      // Try to restore a local PDF draft for this SOW; fall back to saved pdfData.
      PdfEditorArgs? restoredPdfArgs;
      if (doc != null && widget.showPdfEditor && _currentPdfArgs == null) {
        final draftJson = await SowSharedPrefsService()
            .loadPdfDraft(projectId, sowId);
        final pdfJson = draftJson ?? doc.pdfData;
        if (pdfJson != null) {
          restoredPdfArgs = PdfEditorArgs(
            initialData: PdfDocumentData.fromJson(pdfJson),
            apiBaseUrl: ApiConfig.sowProxyBaseUrl,
            companyId: '',
            projectId: projectId,
            frameUrls: doc.frameUrls,
          );
        }
      }
      setState(() {
        _currentSowDoc = doc;
        _sowDocLoading = false;
        if (restoredPdfArgs != null) _currentPdfArgs = restoredPdfArgs;
      });
    } catch (_) {
      if (mounted) setState(() => _sowDocLoading = false);
    }
  }

  void _exitSowDocument() {
    setState(() => _workspaceReloadVersion++);
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    context.go(
      projectId != null ? '/project/$projectId' : AppRoute.home.path,
    );
  }

  void _exitPdfEditor() {
    final sowId = _currentSowId;
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    // Clear linked pdf-document tracking so the next session starts fresh
    // and the user is re-prompted for a name.
    _linkedPdfDocId = null;
    _linkedPdfDocTitle = null;
    // Clear local draft on close so stale data doesn't reappear.
    if (sowId != null && projectId != null) {
      unawaited(SowSharedPrefsService().clearPdfDraft(projectId, sowId));
      context.go('/project/$projectId/sow/$sowId');
    } else if (projectId != null) {
      context.go('/project/$projectId');
    } else {
      context.go(AppRoute.home.path);
    }
  }

  void _openPdfEditorFromDoc(PdfEditorArgs args) {
    final sowId = _currentSowId ?? 'new';
    final projectId = _selectedProject?.id ?? widget.initialProjectId ?? 'demo';
    context.go('/project/$projectId/sow/$sowId/pdf', extra: args);
  }

  /// Saves the current PDF layout as a standalone pdf-document so it shows
  /// up in the project's "PDF Documents" sidebar. First save in a session
  /// prompts for a name; subsequent saves overwrite the same document.
  Future<void> _savePdfToBackend(PdfDocumentData data) async {
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    if (projectId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a project before saving the PDF.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    String title;
    if (_linkedPdfDocId == null) {
      final defaultName = (data.name != null && data.name!.trim().isNotEmpty)
          ? data.name!.trim()
          : (_currentSowDoc?.title ??
              _currentSowDocArgs?.projectName ??
              'Untitled PDF');
      final entered = await _promptForPdfName(defaultName);
      if (entered == null || !mounted) return;
      title = entered;
    } else {
      title = _linkedPdfDocTitle ?? data.name ?? 'Untitled PDF';
    }

    try {
      final saved = await _backendService.savePdfDocument(
        projectId: projectId,
        id: _linkedPdfDocId,
        title: title,
        pdfData: data.toJson(),
      );
      if (!mounted) return;
      setState(() {
        _linkedPdfDocId = saved.id;
        _linkedPdfDocTitle = saved.title;
        // Bump so the sidebar's PDF-documents list re-fetches.
        _workspaceReloadVersion++;
      });
      final sowId = _currentSowId;
      if (sowId != null) {
        unawaited(SowSharedPrefsService().clearPdfDraft(projectId, sowId));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved as “$title”'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save PDF: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<String?> _promptForPdfName(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PDF name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;
    return result.isEmpty ? defaultName : result;
  }

  /// Auto-saves the PDF layout to SharedPreferences (debounce handled in widget).
  void _autoSavePdfDraft(PdfDocumentData data) {
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    final sowId = _currentSowId;
    if (projectId == null || sowId == null || sowId == 'new') return;
    unawaited(
        SowSharedPrefsService().savePdfDraft(projectId, sowId, data.toJson()));
  }

  // ── Standalone PDF document helpers ──────────────────────────────────────

  Future<void> _loadPdfDocument(String pdfDocId) async {
    setState(() => _pdfDocLoading = true);
    try {
      final projectId = widget.initialProjectId ?? _selectedProject?.id;
      if (projectId == null) {
        if (mounted) setState(() => _pdfDocLoading = false);
        return;
      }
      final results = await Future.wait<dynamic>([
        _backendService.getPdfDocument(projectId, pdfDocId),
        if (_selectedProject == null) _backendService.fetchProject(projectId),
      ]);
      if (!mounted) return;
      final doc = results[0] as PdfDocumentModel?;
      if (_selectedProject == null && results.length > 1) {
        final project = results[1] as SowProjectModel?;
        if (project != null) setState(() => _selectedProject = project);
      }
      setState(() {
        _currentPdfDoc = doc;
        _pdfDocLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _pdfDocLoading = false);
    }
  }

  void _exitPdfDocument() {
    setState(() {
      _workspaceReloadVersion++;
      _pendingNewPdfName = null;
    });
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    context.go(
      projectId != null ? '/project/$projectId' : AppRoute.home.path,
    );
  }

  Future<void> _savePdfDocumentToBackend(PdfDocumentData data) async {
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    if (projectId == null) return;
    final docId = _currentPdfDocId == 'new' ? null : _currentPdfDocId;
    final isNew = docId == null;

    String title;
    if (isNew) {
      final preName = _pendingNewPdfName;
      if (preName != null) {
        // Name was entered before the editor opened — use it directly.
        // If the user renamed the doc inside the editor, prefer that.
        title = (data.name != null && data.name!.trim().isNotEmpty)
            ? data.name!.trim()
            : preName;
        // _pendingNewPdfName cleared in the final setState below.
      } else {
        final defaultName = (data.name != null && data.name!.trim().isNotEmpty)
            ? data.name!.trim()
            : 'Untitled PDF';
        final entered = await _promptForPdfName(defaultName);
        if (entered == null || !mounted) return;
        title = entered;
      }
    } else {
      title = _currentPdfDoc?.title ?? data.name ?? 'Untitled PDF';
    }

    try {
      final saved = await _backendService.savePdfDocument(
        projectId: projectId,
        id: docId,
        title: title,
        pdfData: data.toJson(),
      );
      if (mounted) {
        setState(() {
          _currentPdfDoc = saved;
          _currentPdfDocId = saved.id;
          // Bump every save so the project sidebar's PDF list re-fetches
          // even when the user keeps the editor open.
          _workspaceReloadVersion++;
        });
        if (isNew) context.go('/project/$projectId/pdf/${saved.id}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved as “$title”'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save PDF: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _onSowDocumentSaved(String savedDocId) {
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    if (projectId == null) return;
    final isFirstSave = _currentSowId != savedDocId;
    setState(() {
      _currentSowId = savedDocId;
      // Re-key the workspace so the sidebar's SOW docs list re-fetches
      // after every save (not just the first).
      _workspaceReloadVersion++;
    });
    if (isFirstSave) {
      context.go('/project/$projectId/sow/$savedDocId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredProjects = _filteredProjects();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isPhone = screenWidth < 760;
        final isTablet = screenWidth >= 760 && screenWidth < 1200;
        final sidebarWidth = isTablet ? 320.0 : 360.0;

        if (isPhone) {
          // On mobile, SOW doc / PDF editor replace the whole layout.
          if (_currentPdfDocId != null) {
            if (_pdfDocLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final initialData = _currentPdfDoc != null
                ? _currentPdfDoc!.toPdfDocumentData()
                : PdfDocumentData.empty(name: 'Untitled PDF');
            return DeferredLoader(
              loadLibrary: pdf_editor.loadLibrary,
              builder: (context) => pdf_editor.PdfEditorWidget(
                initialData: initialData,
                apiBaseUrl: ApiConfig.sowProxyBaseUrl,
                companyId: '',
                projectId: _selectedProject?.id ?? widget.initialProjectId,
                frameUrls: const [],
                tokenProvider: widget.tokenProvider,
                onClose: _exitPdfDocument,
                onSave: _savePdfDocumentToBackend,
                onTemplateSaved: _loadTemplates,
              ),
            );
          }
          if (_showPdfEditor && _currentPdfArgs != null) {
            return DeferredLoader(
              loadLibrary: pdf_editor.loadLibrary,
              builder: (context) => pdf_editor.PdfEditorWidget(
                initialData: _currentPdfArgs!.initialData,
                apiBaseUrl: _currentPdfArgs!.apiBaseUrl,
                companyId: _currentPdfArgs!.companyId,
                projectId: _currentPdfArgs!.projectId ??
                    _selectedProject?.id ??
                    widget.initialProjectId,
                frameUrls: _currentPdfArgs!.frameUrls,
                tokenProvider:
                    _currentPdfArgs!.tokenProvider ?? widget.tokenProvider,
                onClose: _exitPdfEditor,
                onSave: _savePdfToBackend,
                onSnapshot: _autoSavePdfDraft,
                onTemplateSaved: _loadTemplates,
              ),
            );
          }
          if (_currentSowId != null) {
            if (_sowDocLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final args = _currentSowDocArgs;
            final doc = _currentSowDoc;
            if (args != null) {
              return SowDocumentScreen(
                projectName: args.projectName,
                initialContent: args.initialContent,
                clientName: args.clientName,
                siteLocation: args.siteLocation,
                scopeSummary: args.scopeSummary,
                projectId: args.projectId ?? _selectedProject?.id,
                documentId: args.documentId,
                transcriptIds: args.transcriptIds,
                frameUrls: args.frameUrls,
                sowTemplates: _templates,
                pdfTemplates: _pdfTemplates,
                backendService: args.backendService ?? _backendService,
                onBack: _exitSowDocument,
                onOpenPdfEditor: _openPdfEditorFromDoc,
                onDocumentSaved: _onSowDocumentSaved,
              );
            }
            if (doc != null) {
              return SowDocumentScreen(
                projectName: _selectedProject?.name ?? '',
                initialContent: doc.content,
                clientName: _selectedProject?.clientName ?? '',
                siteLocation: _selectedProject?.siteLocation ?? '',
                scopeSummary: _selectedProject?.scopeSummary ?? '',
                projectId: _selectedProject?.id,
                documentId: doc.id,
                transcriptIds: doc.transcriptIds,
                frameUrls: doc.frameUrls,
                sowTemplates: _templates,
                pdfTemplates: _pdfTemplates,
                backendService: _backendService,
                onBack: _exitSowDocument,
                onOpenPdfEditor: _openPdfEditorFromDoc,
                onDocumentSaved: _onSowDocumentSaved,
              );
            }
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _exitSowDocument,
                ),
                title: const Text('Document not found'),
              ),
              body: const Center(child: Text('Could not load document.')),
            );
          }
          return _MobileLayout(
            loading: _loading,
            errorMessage: _errorMessage,
            projects: _projects,
            filteredProjects: filteredProjects,
            selectedProject: _selectedProject,
            selectedTranscripts: _selectedTranscripts,
            creatingProject: _creatingProject,
            searchController: _searchController,
            onSearchChanged: () => setState(() {}),
            onCreateProject: _openCreateProjectDialog,
            onSelectProject: (project) async {
              await _selectProject(project);
            },
            onRefresh: _loadProjects,
            onProjectChanged: _handleProjectChanged,
            onGoToProjects: () => context.go(AppRoute.home.path),
            onDeleteProject: _deleteProject,
            backendService: _backendService,
            initialTab: _currentTab,
          );
        }

        final sidebar = _SidebarPanel(
          loading: _loading,
          errorMessage: _errorMessage,
          searchController: _searchController,
          onSearchChanged: () => setState(() {}),
          projects: filteredProjects,
          selectedProjectId: _selectedProject?.id,
          onCreateProjectTap: _openCreateProjectDialog,
          onSelectProject: _selectProject,
          templates: _templates,
          pdfTemplates: _pdfTemplates,
          templatesLoading: _templatesLoading,
          onOpenTemplate: (template) => SowDocumentScreen.show(
            context,
            projectName: template.name,
            content: template.content,
            backendService: null,
          ),
          onDeleteTemplate: _deleteTemplate,
          onUsePdfTemplate: _usePdfTemplate,
          onDeletePdfTemplate: _deletePdfTemplate,
          onCreateTemplate: _createTemplate,
          embedded: true,
        );

        return Scaffold(
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: sidebarWidth,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      right: BorderSide(color: AppColors.borderStrong),
                    ),
                  ),
                  child: sidebar,
                ),
                Expanded(
                  child: _buildDesktopMainPanel(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopMainPanel() {
    final activeProjectId =
        _selectedProject?.id ?? widget.initialProjectId;
    // Standalone PDF document mode.
    if (_currentPdfDocId != null) {
      if (_pdfDocLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final initialData = _currentPdfDoc != null
          ? _currentPdfDoc!.toPdfDocumentData()
          : PdfDocumentData.empty(name: _pendingNewPdfName ?? 'Untitled PDF');
      return DeferredLoader(
        loadLibrary: pdf_editor.loadLibrary,
        builder: (context) => pdf_editor.PdfEditorWidget(
          initialData: initialData,
          apiBaseUrl: ApiConfig.sowProxyBaseUrl,
          companyId: '',
          projectId: activeProjectId,
          frameUrls: const [],
          tokenProvider: widget.tokenProvider,
          onClose: _exitPdfDocument,
          onSave: _savePdfDocumentToBackend,
          onSnapshot: _autoSavePdfDraft,
          onTemplateSaved: _loadTemplates,
        ),
      );
    }

    // SOW-linked PDF editor takes over the entire right panel.
    if (_showPdfEditor) {
      if (_sowDocLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final args = _currentPdfArgs;
      if (args != null) {
        return DeferredLoader(
          loadLibrary: pdf_editor.loadLibrary,
          builder: (context) => pdf_editor.PdfEditorWidget(
            initialData: args.initialData,
            apiBaseUrl: args.apiBaseUrl,
            companyId: args.companyId,
            projectId: args.projectId ?? activeProjectId,
            frameUrls: args.frameUrls,
            tokenProvider: args.tokenProvider ?? widget.tokenProvider,
            onClose: _exitPdfEditor,
            onSave: _savePdfToBackend,
            onSnapshot: _autoSavePdfDraft,
            onTemplateSaved: _loadTemplates,
          ),
        );
      }
      return _SessionExpiredPanel(onAction: _exitSowDocument);
    }

    // SOW document panel.
    if (_currentSowId != null) {
      if (_sowDocLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final args = _currentSowDocArgs;
      final doc = _currentSowDoc;
      if (args != null) {
        return SowDocumentScreen(
          projectName: args.projectName,
          initialContent: args.initialContent,
          clientName: args.clientName,
          siteLocation: args.siteLocation,
          scopeSummary: args.scopeSummary,
          projectId: args.projectId ?? _selectedProject?.id,
          documentId: args.documentId,
          transcriptIds: args.transcriptIds,
          frameUrls: args.frameUrls,
          sowTemplates: _templates,
          pdfTemplates: _pdfTemplates,
          backendService: args.backendService ?? _backendService,
          onBack: _exitSowDocument,
          onOpenPdfEditor: _openPdfEditorFromDoc,
          onDocumentSaved: _onSowDocumentSaved,
        );
      }
      if (doc != null) {
        return SowDocumentScreen(
          projectName: _selectedProject?.name ?? '',
          initialContent: doc.content,
          clientName: _selectedProject?.clientName ?? '',
          siteLocation: _selectedProject?.siteLocation ?? '',
          scopeSummary: _selectedProject?.scopeSummary ?? '',
          projectId: _selectedProject?.id,
          documentId: doc.id,
          transcriptIds: doc.transcriptIds,
          frameUrls: doc.frameUrls,
          sowTemplates: _templates,
          pdfTemplates: _pdfTemplates,
          backendService: _backendService,
          onBack: _exitSowDocument,
          onOpenPdfEditor: _openPdfEditorFromDoc,
          onDocumentSaved: _onSowDocumentSaved,
        );
      }
      return _DocNotFoundPanel(onAction: _exitSowDocument);
    }

    // Default workspace: top bar + project workspace.
    return Column(
      children: [
        _ShellTopBar(
          projectCount: _projects.length,
          selectedProject: _selectedProject,
          creatingProject: _creatingProject,
          onRefresh: () {
            _loadProjects();
            _loadTemplates();
          },
          onCreateProject: _openCreateProjectDialog,
        ),
        const Divider(height: 1),
        Expanded(
          child: _MainWorkspacePanel(
            key: ValueKey(
              'workspace-${_selectedProject?.id ?? 'none'}-$_workspaceReloadVersion',
            ),
            selectedProject: _selectedProject,
            transcripts: _selectedTranscripts,
            onProjectChanged: _handleProjectChanged,
            backendService: _backendService,
            embedded: true,
          ),
        ),
      ],
    );
  }

  List<SowProjectModel> _filteredProjects() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _projects;
    }

    return _projects
        .where((project) {
          return project.name.toLowerCase().contains(query) ||
              project.clientName.toLowerCase().contains(query) ||
              project.siteLocation.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _loadProjects() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      var projects = await _backendService.fetchProjects();
      projects = await _filterProjectsByViewPermission(projects);
      setState(() {
        _projects = projects;
        if (_selectedProject != null) {
          _selectedProject = projects.firstWhere(
            (project) => project.id == _selectedProject!.id,
            orElse:
                () =>
                    projects.isNotEmpty ? projects.first : _selectedProject!,
          );
        } else if (widget.initialProjectId != null) {
          // Auto-select the project indicated by the URL on initial load.
          final matches = projects.where((p) => p.id == widget.initialProjectId);
          if (matches.isNotEmpty) _selectedProject = matches.first;
        }
        // On initial load with no initialProjectId, leave null — don't auto-select.
      });

      if (_selectedProject != null) {
        await _loadSelectedProject(_selectedProject!.id);
      } else {
        setState(() {
          _selectedTranscripts = <SowTranscriptModel>[];
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// For members, hide any project where their permission record has
  /// canView == false. Owners/guests see everything.
  Future<List<SowProjectModel>> _filterProjectsByViewPermission(
    List<SowProjectModel> projects,
  ) async {
    final auth = context.read<AuthController>();
    final user = auth.user;
    if (user == null || user.isOwner || user.isGuest) return projects;
    try {
      final perms = await auth.listPermissions();
      final hidden = <String>{
        for (final p in perms)
          if (p.uid == user.uid && !p.canView) p.projectId,
      };
      if (hidden.isEmpty) return projects;
      return projects
          .where((p) => !hidden.contains(p.id))
          .toList(growable: false);
    } catch (_) {
      return projects;
    }
  }

  Future<void> _loadSelectedProject(String projectId) async {
    try {
      final project = await _backendService.fetchProject(projectId);
      final transcripts = await _backendService.fetchHistory(projectId);
      if (!mounted || project == null) {
        return;
      }

      setState(() {
        _selectedProject = project;
        _selectedTranscripts = transcripts;
        _projects = _projects
            .map((item) => item.id == project.id ? project : item)
            .toList(growable: false);
      });
    } on SowPermissionException {
      // Member lacks view permission on this project — silently drop the
      // selection rather than showing a scary error banner.
      if (mounted) {
        setState(() {
          _selectedProject = null;
          _selectedTranscripts = const <SowTranscriptModel>[];
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    }
  }

  /// Optimistically creates a project: fires the backend call in the background
  /// while the UI is already showing the creating state. The dialog is closed
  /// by the caller before this method is invoked.
  Future<void> _backgroundCreateProject() async {
    final name = _nameController.text.trim();
    final clientName = _clientController.text.trim();
    final siteLocation = _siteController.text.trim();
    final scopeSummary = _scopeController.text.trim();
    final notes = _notesController.text.trim();

    // Clear form fields straight away — the dialog is already dismissed.
    _nameController.clear();
    _clientController.clear();
    _siteController.clear();
    _scopeController.clear();
    _notesController.clear();

    final createdBy = context.read<AuthController>().user?.uid ?? '';

    setState(() {
      _creatingProject = true;
      _errorMessage = null;
    });

    try {
      final project = await _backendService.createProject(
        name: name,
        clientName: clientName,
        siteLocation: siteLocation,
        scopeSummary: scopeSummary,
        notes: notes,
        createdBy: createdBy,
        status: ApiConfig.defaultProjectStatus,
      );

      if (!mounted) return;
      setState(() {
        _projects = <SowProjectModel>[project, ..._projects];
        _selectedProject = project;
        _selectedTranscripts = <SowTranscriptModel>[];
      });
      // Update URL so a browser refresh lands back on this project.
      context.go('/project/${project.id}');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create project: $error'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _creatingProject = false);
      }
    }
  }

  Future<void> _openCreateProjectDialog() async {
    _nameController.clear();
    _clientController.clear();
    _siteController.clear();
    _scopeController.clear();
    _notesController.clear();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _CreateProjectDialog(
          nameController: _nameController,
          clientController: _clientController,
          siteController: _siteController,
          scopeController: _scopeController,
          notesController: _notesController,
          // Dialog closes immediately on successful validation; creation runs in background.
          onSubmit: () => unawaited(_backgroundCreateProject()),
        );
      },
    );
  }

  Future<void> _selectProject(SowProjectModel project) async {
    if (_selectedProject?.id == project.id) return;
    // Navigate to the project URL — didUpdateWidget handles the actual selection
    // and transcript load, keeping _projects and all other state intact.
    context.go('/project/${project.id}');
  }

  Future<void> _handleProjectChanged() async {
    if (_selectedProject == null) {
      return;
    }

    // Run both refreshes in parallel for a faster combined response.
    await Future.wait([
      _loadSelectedProject(_selectedProject!.id),
      _loadProjects(),
    ]);
  }

  Future<void> _deleteProject(String projectId) async {
    final previousProjects = List<SowProjectModel>.from(_projects);
    final previousSelected = _selectedProject;
    // Optimistic: remove from list and navigate back to home immediately.
    setState(() {
      _selectedProject = null;
      _selectedTranscripts = [];
      _projects = _projects
          .where((p) => p.id != projectId)
          .toList(growable: false);
    });
    if (mounted) context.go(AppRoute.home.path);
    try {
      await _backendService.deleteProject(projectId);
    } catch (e) {
      // Rollback on failure.
      setState(() {
        _projects = previousProjects;
        _selectedProject = previousSelected;
      });
      if (mounted) {
        // Restore the project URL as well.
        if (previousSelected != null) {
          context.go('/project/${previousSelected.id}');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete project: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          ),
        );
      }
    }
  }

  Future<void> _loadTemplates() async {
    setState(() => _templatesLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        _backendService.fetchTemplates(),
        _backendService.fetchPdfTemplates().catchError(
          (_) => <Map<String, dynamic>>[],
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<SowTemplateModel>;
        _pdfTemplates = results[1] as List<Map<String, dynamic>>;
      });
    } catch (_) {
      // Non-critical — silently ignore template load errors.
    } finally {
      if (mounted) setState(() => _templatesLoading = false);
    }
  }

  Future<void> _deletePdfTemplate(String templateId) async {
    final previous = List<Map<String, dynamic>>.from(_pdfTemplates);
    setState(() => _pdfTemplates =
        _pdfTemplates.where((t) => t['id'] != templateId).toList());
    try {
      await _backendService.deletePdfTemplate(templateId);
    } catch (_) {
      if (mounted) setState(() => _pdfTemplates = previous);
    }
  }

  Future<void> _usePdfTemplate(Map<String, dynamic> tpl) async {
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    if (projectId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a project before using a PDF template.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final pdfJson = tpl['pdfJson'];
    if (pdfJson is! Map<String, dynamic>) return;
    try {
      final saved = await _backendService.savePdfDocument(
        projectId: projectId,
        title: (tpl['name'] as String?)?.trim().isNotEmpty == true
            ? tpl['name'] as String
            : 'Untitled PDF',
        pdfData: pdfJson,
      );
      if (!mounted) return;
      setState(() => _workspaceReloadVersion++);
      context.go('/project/$projectId/pdf/${saved.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open template: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _createTemplate() async {
    final projectId = _selectedProject?.id ?? widget.initialProjectId;
    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a project before creating a PDF.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New PDF'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PDF name',
            hintText: 'e.g. "Proposal for Client A"',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (confirmed != true || !mounted) return;

    final finalName = name.isEmpty ? 'Untitled PDF' : name;
    _pendingNewPdfName = finalName;
    context.go('/project/$projectId/pdf/new');
  }

  Future<void> _deleteTemplate(String templateId) async {
    final previous = List<SowTemplateModel>.from(_templates);
    setState(() => _templates = _templates.where((t) => t.id != templateId).toList());
    try {
      await _backendService.deleteTemplate(templateId);
    } catch (_) {
      if (mounted) setState(() => _templates = previous);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEW: Mobile Layout — 3-tab bottom nav replacing old Drawer-based layout
// ─────────────────────────────────────────────────────────────────────────────

class _MobileLayout extends StatefulWidget {
  const _MobileLayout({
    required this.loading,
    required this.errorMessage,
    required this.projects,
    required this.filteredProjects,
    required this.selectedProject,
    required this.selectedTranscripts,
    required this.creatingProject,
    required this.searchController,
    required this.onSearchChanged,
    required this.onCreateProject,
    required this.onSelectProject,
    required this.onRefresh,
    required this.onProjectChanged,
    required this.onGoToProjects,
    required this.onDeleteProject,
    required this.backendService,
    this.initialTab,
  });

  final bool loading;
  final String? errorMessage;
  final List<SowProjectModel> projects;
  final List<SowProjectModel> filteredProjects;
  final SowProjectModel? selectedProject;
  final List<SowTranscriptModel> selectedTranscripts;
  final bool creatingProject;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final VoidCallback onCreateProject;
  final Future<void> Function(SowProjectModel project) onSelectProject;
  final VoidCallback onRefresh;
  final Future<void> Function() onProjectChanged;
  final VoidCallback onGoToProjects;
  final Future<void> Function(String projectId) onDeleteProject;
  final SowBackendService backendService;
  final String? initialTab;

  @override
  State<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<_MobileLayout> {
  @override
  Widget build(BuildContext context) {
    // No project selected → full-screen projects list
    if (widget.selectedProject == null) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: _MobileProjectsTab(
            loading: widget.loading,
            errorMessage: widget.errorMessage,
            projects: widget.filteredProjects,
            allProjects: widget.projects,
            selectedProjectId: null,
            searchController: widget.searchController,
            onSearchChanged: widget.onSearchChanged,
            onCreateProject: widget.onCreateProject,
            onRefresh: widget.onRefresh,
            onSelectProject: widget.onSelectProject,
          ),
        ),
      );
    }

    // Project selected → workspace with Record / History sub-tabs
    return MultiProvider(
      providers: [
        Provider<GeminiLiveService>(
          create: (_) => createGeminiLiveService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<SowBackendService>.value(value: widget.backendService),
        Provider<SowSharedPrefsService>(create: (_) => SowSharedPrefsService()),
        ChangeNotifierProvider<SowRecordingController>(
          key: ValueKey<String>('mobile-${widget.selectedProject!.id}'),
          create:
              (context) =>
                  SowRecordingController(
                      projectId: widget.selectedProject!.id,
                      createdBy: context.read<AuthController>().user?.uid ?? '',
                      sowBackendService: context.read<SowBackendService>(),
                      geminiLiveService: context.read<GeminiLiveService>(),
                      sharedPrefsService: context.read<SowSharedPrefsService>(),
                      onAutosaveCompleted: widget.onProjectChanged,
                    )
                    ..loadHistory(widget.selectedProject!.id)
                    ..restoreAutosavedDraft(),
        ),
      ],
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: _MobileProjectWorkspace(
            project: widget.selectedProject!,
            transcripts: widget.selectedTranscripts,
            onProjectChanged: widget.onProjectChanged,
            onGoToProjects: widget.onGoToProjects,
            onDeleteProject: widget.onDeleteProject,
            initialTab: widget.initialTab,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 0: Projects
// ─────────────────────────────────────────────────────────────────────────────

class _MobileProjectsTab extends StatelessWidget {
  const _MobileProjectsTab({
    required this.loading,
    required this.errorMessage,
    required this.projects,
    required this.allProjects,
    required this.selectedProjectId,
    required this.searchController,
    required this.onSearchChanged,
    required this.onCreateProject,
    required this.onRefresh,
    required this.onSelectProject,
  });

  final bool loading;
  final String? errorMessage;
  final List<SowProjectModel> projects;
  final List<SowProjectModel> allProjects;
  final String? selectedProjectId;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final VoidCallback onCreateProject;
  final VoidCallback onRefresh;
  final Future<void> Function(SowProjectModel project) onSelectProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AppBar area
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Scope Projects',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
              ),
              IconButton(
                onPressed: onCreateProject,
                icon: const Icon(Icons.add_rounded),
                visualDensity: VisualDensity.compact,
                tooltip: 'New Project',
              ),
              _UserMenuButton(compact: true),
            ],
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: searchController,
            onChanged: (_) => onSearchChanged(),
            decoration: AppInputs.search(hintText: 'Search projects'),
          ),
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _InlineMessage(message: errorMessage!, isError: true),
          ),
        // Loading indicator
        if (loading && projects.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 12),
        // Project list
        Expanded(
          child:
              loading && projects.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : projects.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _EmptyProjectsState(
                        onCreateProjectTap: onCreateProject,
                      ),
                    ),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: projects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return _ProjectListTile(
                        project: project,
                        selected: project.id == selectedProjectId,
                        onTap: () => onSelectProject(project),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Project Workspace — Record + History as internal sub-tabs inside a project
// ─────────────────────────────────────────────────────────────────────────────

class _MobileProjectWorkspace extends StatefulWidget {
  const _MobileProjectWorkspace({
    required this.project,
    required this.transcripts,
    required this.onProjectChanged,
    required this.onGoToProjects,
    required this.onDeleteProject,
    this.initialTab,
  });

  final SowProjectModel project;
  final List<SowTranscriptModel> transcripts;
  final Future<void> Function() onProjectChanged;
  final VoidCallback onGoToProjects;
  final Future<void> Function(String projectId) onDeleteProject;
  /// 'record' (default) or 'transcripts'. Synced to URL query param ?tab=.
  final String? initialTab;

  @override
  State<_MobileProjectWorkspace> createState() =>
      _MobileProjectWorkspaceState();
}

class _MobileProjectWorkspaceState extends State<_MobileProjectWorkspace>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  /// True while we are programmatically changing the tab to prevent the
  /// listener from pushing a redundant context.go() back to the router.
  bool _updatingFromRoute = false;

  /// Bumped to trigger a reload of the Documents tab (e.g. after a SOW is
  /// generated or when the Documents tab becomes active).
  final ValueNotifier<int> _docsReload = ValueNotifier<int>(0);

  static int _indexForTab(String? tab) {
    switch (tab) {
      case 'transcripts':
        return 1;
      case 'documents':
        return 2;
      default:
        return 0;
    }
  }

  static String _tabForIndex(int index) {
    switch (index) {
      case 1:
        return 'transcripts';
      case 2:
        return 'documents';
      default:
        return 'record';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _indexForTab(widget.initialTab),
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    // Skip intermediate animation frames and programmatic updates.
    if (_tabController.indexIsChanging) return;
    // Refresh documents whenever the Documents tab becomes active.
    if (_tabController.index == 2) _docsReload.value++;
    if (_updatingFromRoute) {
      _updatingFromRoute = false;
      return;
    }
    final tab = _tabForIndex(_tabController.index);
    // Only push a URL update if the tab actually differs from the current URL.
    final currentRouteTab = widget.initialTab ?? 'record';
    if (tab == currentRouteTab) return;
    context.go('/project/${widget.project.id}?tab=$tab');
  }

  @override
  void didUpdateWidget(_MobileProjectWorkspace old) {
    super.didUpdateWidget(old);
    if (widget.initialTab != old.initialTab && widget.initialTab != null) {
      final idx = _indexForTab(widget.initialTab);
      if (_tabController.index != idx) {
        _updatingFromRoute = true;
        _tabController.animateTo(idx);
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _docsReload.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteProject(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'This permanently deletes "${widget.project.name}", all its transcripts, and all video images. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onDeleteProject(widget.project.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Project header with back button
        Container(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onGoToProjects,
                tooltip: 'All projects',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.project.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.project.clientName.isNotEmpty)
                      Text(
                        '${widget.project.clientName}'
                        '${widget.project.siteLocation.isNotEmpty ? ' · ${widget.project.siteLocation}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodyMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: widget.project.statusLabel),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmDeleteProject(context),
                tooltip: 'Delete project',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
        // Record / Transcripts / Documents tab bar
        Material(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.mic_rounded, size: 18), text: 'Record'),
              Tab(
                icon: Icon(Icons.description_rounded, size: 18),
                text: 'Transcripts',
              ),
              Tab(
                icon: Icon(Icons.folder_open_rounded, size: 18),
                text: 'Documents',
              ),
            ],
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.bodyMuted,
          ),
        ),
        const Divider(height: 1),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MobileWorkspaceContent(
                project: widget.project,
                transcripts: widget.transcripts,
                onProjectChanged: widget.onProjectChanged,
                onGoToHistory: () => _tabController.animateTo(1),
              ),
              _MobileHistoryTab(
                selectedProject: widget.project,
                selectedTranscripts: widget.transcripts,
                onProjectChanged: widget.onProjectChanged,
                onGoToRecord: () => _tabController.animateTo(0),
                onSowGenerated: () => _docsReload.value++,
              ),
              _DocumentsPanel(
                project: widget.project,
                reload: _docsReload,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-screen mobile workspace — providers + Consumer wired up here
class _MobileWorkspaceContent extends StatefulWidget {
  const _MobileWorkspaceContent({
    required this.project,
    required this.transcripts,
    required this.onProjectChanged,
    required this.onGoToHistory,
  });

  final SowProjectModel project;
  final List<SowTranscriptModel> transcripts;
  final Future<void> Function() onProjectChanged;
  final VoidCallback onGoToHistory;

  @override
  State<_MobileWorkspaceContent> createState() =>
      _MobileWorkspaceContentState();
}

class _MobileWorkspaceContentState extends State<_MobileWorkspaceContent> {
  String? _lastErrorMessage;
  final TextEditingController _draftController = TextEditingController();
  bool _suppressDraftCallback = false;

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SowRecordingController>(
      builder: (context, controller, _) {
        _handleError(context, controller);
        _syncDraftFromController(controller);

        final isRecording =
            controller.recordingState == RecordingState.recording;
        final isSaving = controller.recordingState == RecordingState.saving;
        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [B] Transcript editor — expands to fill space
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.borderStrong),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Editor header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Transcript editor',
                            style: theme.textTheme.labelLarge,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.blue100,
                            ),
                            child: Text(
                              controller.activeTranscriptId == null
                                  ? 'New draft'
                                  : 'Saved',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          if (isRecording)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: AppColors.dangerLight,
                              ),
                              child: Text(
                                'Recording live',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Recording status bar
                    if (isRecording) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: RecordingStatusBar(
                          elapsedSeconds: controller.elapsedSeconds,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // The actual text field — fills remaining space
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: TextField(
                          controller: _draftController,
                          onChanged: (value) {
                            if (_suppressDraftCallback) return;
                            controller.updateDraft(value);
                          },
                          minLines: null,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: AppInputs.multiline(
                            labelText: 'Transcript draft',
                            hintText:
                                'Live transcript appears here. Edit any words before saving.',
                            fillColor: AppColors.surface,
                          ),
                        ),
                      ),
                    ),
                    // Frame thumbnails (when a video transcript is loaded)
                    if (controller.activeFrameUrls.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                        child: SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            itemCount: controller.activeFrameUrls.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(width: 6),
                            itemBuilder: (_, i) => ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                              child: Image.network(
                                controller.activeFrameUrls[i],
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 72,
                                  height: 72,
                                  color: AppColors.surfaceRaised,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    size: 20,
                                    color: AppColors.bodyMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    // Helper text
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Text(
                        controller.hasPendingResync
                            ? 'New speech detected — tap Resync to merge.'
                            : controller.hasLocalEdits
                            ? 'Draft edited locally. Save when ready.'
                            : controller.hasDraft
                            ? 'Next recording will append to this draft.'
                            : 'Next recording will start a new transcript.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodyMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // [C] Secondary actions: Reset + Resync (icon buttons) + Save
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: !isSaving &&
                            controller.draftTranscript.trim().isNotEmpty
                        ? () => controller.resetDraft()
                        : null,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    tooltip: 'Reset draft',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.bodyMuted,
                    ),
                  ),
                  IconButton(
                    onPressed: !isSaving &&
                            (controller.hasPendingResync ||
                                controller.hasLocalEdits)
                        ? controller.resyncDraft
                        : null,
                    icon: const Icon(Icons.sync_rounded, size: 20),
                    tooltip: 'Resync transcript',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.bodyMuted,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: isSaving ||
                            controller.draftTranscript.trim().isEmpty
                        ? null
                        : () async {
                            final title =
                                await _promptTranscriptTitle(context);
                            if (!context.mounted) return;
                            await controller.saveDraft(title: title);
                            if (!context.mounted) return;
                            // Navigate to history immediately — saveDraft is already
                            // optimistic, the transcript is visible right away.
                            widget.onGoToHistory();
                            // Refresh project metadata in the background.
                            unawaited(widget.onProjectChanged());
                          },
                    icon: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(isSaving ? 'Saving…' : 'Save Transcript'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // [D] Primary action row: Video (big) + Record/Stop (compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: isRecording || isSaving
                            ? null
                            : () => _openVideoFeed(context, controller),
                        icon: const Icon(Icons.videocam_rounded, size: 20),
                        label: const Text(
                          'Video',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: isRecording || isSaving
                              ? AppColors.bodyMuted
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                        onPressed: isSaving
                            ? null
                            : () async {
                                HapticFeedback.lightImpact();
                                if (isRecording) {
                                  await controller.stopRecording();
                                  return;
                                }
                                final auth =
                                    context.read<AuthController>();
                                final perm = await auth
                                    .permissionsForProject(widget.project.id);
                                if (!perm.canRecord) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "You don't have permission to record on this project.",
                                      ),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                  return;
                                }
                                await controller.startRecording();
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: isSaving
                              ? AppColors.bodyMuted
                              : isRecording
                                  ? AppColors.danger
                                  : AppColors.surfaceRaised,
                          foregroundColor: isSaving || isRecording
                              ? Colors.white
                              : AppColors.body,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                        ),
                        icon: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isRecording
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                              ),
                        label: Text(
                          isSaving
                              ? 'Processing…'
                              : isRecording
                                  ? 'Stop'
                                  : 'Mic',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _openVideoFeed(
      BuildContext context, SowRecordingController controller) {
    context.pushNamed(
      AppRoute.videoFeed.name,
      pathParameters: {'projectId': widget.project.id},
      extra: VideoFeedArgs(
        projectId: widget.project.id,
        onFeedComplete: (frames, transcript) {
          if (transcript.isNotEmpty) {
            final current = controller.draftTranscript;
            final appended =
                current.isNotEmpty ? '$current\n\n$transcript' : transcript;
            controller.updateDraft(appended);
          }
          if (frames.isNotEmpty) {
            _uploadVideoFrames(
              controller: controller,
              projectId: widget.project.id,
              frames: frames,
              context: context,
            );
          }
        },
      ),
    );
  }

  /// Uploads [frames] to Firebase Storage and sets the URLs on the controller
  /// so they are available when the user manually saves the draft.
  Future<void> _uploadVideoFrames({
    required SowRecordingController controller,
    required String projectId,
    required List<dynamic> frames,
    required BuildContext context,
  }) async {
    try {
      final frameUrls = await const VideoFrameStorageService().uploadFrames(
        projectId: projectId,
        frames: frames.cast(),
      );
      if (frameUrls.isNotEmpty) {
        controller.updateActiveFrameUrls(frameUrls);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not upload video frames: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  void _syncDraftFromController(SowRecordingController controller) {
    if (_draftController.text == controller.draftTranscript) return;
    _suppressDraftCallback = true;
    _draftController.value = TextEditingValue(
      text: controller.draftTranscript,
      selection: TextSelection.collapsed(
        offset: controller.draftTranscript.length,
      ),
    );
    _suppressDraftCallback = false;
  }

  void _handleError(BuildContext context, SowRecordingController controller) {
    final message = controller.errorMessage;
    if (message == null || message == _lastErrorMessage) return;
    _lastErrorMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        ),
      );
      context.read<SowRecordingController>().clearError();
    });
  }

  Future<String?> _promptTranscriptTitle(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      builder: (_) => const _TitlePromptSheet(),
    ).then((result) => result?.isEmpty == true ? null : result);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Title prompt sheet — owns its own TextEditingController lifecycle
// ─────────────────────────────────────────────────────────────────────────────

class _TitlePromptSheet extends StatefulWidget {
  const _TitlePromptSheet();

  @override
  State<_TitlePromptSheet> createState() => _TitlePromptSheetState();
}

class _TitlePromptSheetState extends State<_TitlePromptSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Name this transcript',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional \u2014 helps identify it in the history list.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.bodyMuted,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. "Kitchen wall repair"',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_ctrl.text.trim()),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: History
// ─────────────────────────────────────────────────────────────────────────────

class _MobileHistoryTab extends StatefulWidget {
  const _MobileHistoryTab({
    required this.selectedProject,
    required this.selectedTranscripts,
    required this.onProjectChanged,
    required this.onGoToRecord,
    required this.onSowGenerated,
  });

  final SowProjectModel? selectedProject;
  final List<SowTranscriptModel> selectedTranscripts;
  final Future<void> Function() onProjectChanged;
  final VoidCallback onGoToRecord;
  final VoidCallback onSowGenerated;

  @override
  State<_MobileHistoryTab> createState() => _MobileHistoryTabState();
}

class _MobileHistoryTabState extends State<_MobileHistoryTab> {
  final Set<String> _selectedIds = {};
  bool _selectMode = false;

  bool get _isSelecting => _selectMode || _selectedIds.isNotEmpty;

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(() {
    _selectedIds.clear();
    _selectMode = false;
  });

  void _enterSelectMode() => setState(() => _selectMode = true);

  Future<void> _onGenerateSow(
    BuildContext context,
    SowProjectModel project,
    List<SowTranscriptModel> transcripts,
  ) async {
    final selected =
        transcripts.where((t) => _selectedIds.contains(t.id)).toList();
    if (selected.isEmpty) return;

    // Read services and navigator before any async gap.
    final backendService = context.read<SowBackendService>();
    final sharedPrefsService = context.read<SowSharedPrefsService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating SOW…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Load persisted SOW settings.
    final settings = await sharedPrefsService.loadSowSettings();

    try {
      final transcriptIds = selected.map((t) => t.id).toList();
      final sow = await backendService.generateSow(
        projectId: project.id,
        transcriptIds: transcriptIds,
        settings: settings,
      );
      navigator.pop();
      if (!context.mounted) return;
      _clearSelection();
      await SowDocumentScreen.show(
        context,
        projectName: project.name,
        content: sow,
        clientName: project.clientName,
        siteLocation: project.siteLocation,
        scopeSummary: project.scopeSummary,
        projectId: project.id,
        transcriptIds: transcriptIds,
        frameUrls: selected.expand((t) => t.frameUrls).toList(),
        backendService: backendService,
      );
      // Reload saved SOWs after returning from the document screen
      widget.onSowGenerated();
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to generate SOW: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        ),
      );
    }
  }

  void _showPreview(BuildContext context, SowTranscriptModel transcript) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      builder: (_) => _TranscriptPreviewSheet(transcript: transcript),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<SowRecordingController>(
      builder: (context, controller, _) {
        final transcripts =
            controller.historyLoaded
                ? controller.history
                : widget.selectedTranscripts;
        // Drop stale selection IDs that were removed from the list.
        final staleIds =
            _selectedIds
                .where((id) => transcripts.every((t) => t.id != id))
                .toSet();
        if (staleIds.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => setState(() => _selectedIds.removeAll(staleIds)),
          );
        }
        final isBusy =
            controller.recordingState == RecordingState.recording ||
            controller.recordingState == RecordingState.saving;
        final hasUnsavedDraft =
            controller.hasDraft && controller.activeTranscriptId == null;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar — switches between info/actions and selection mode
                if (_isSelecting)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    decoration: const BoxDecoration(
                      color: AppColors.blue100,
                      border: Border(
                        bottom: BorderSide(color: AppColors.borderStrong),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_selectedIds.length} selected',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_selectedIds.length == transcripts.length) {
                                _selectedIds.clear();
                              } else {
                                _selectedIds.addAll(
                                  transcripts.map((t) => t.id),
                                );
                              }
                            });
                          },
                          child: Text(
                            _selectedIds.length == transcripts.length
                                ? 'Deselect all'
                                : 'Select all',
                          ),
                        ),
                        TextButton(
                          onPressed: _clearSelection,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (hasUnsavedDraft)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: AppColors.blue100,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Unsaved draft active — go to Record to save it.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed:
                                isBusy
                                    ? null
                                    : () async {
                                      await controller.resetDraft();
                                      widget.onGoToRecord();
                                    },
                            icon: const Icon(Icons.note_add_outlined),
                            label: const Text('Start New Transcript'),
                          ),
                        ),
                        if (transcripts.isNotEmpty) ...[  
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 44,
                            child: FilledButton.icon(
                              onPressed: isBusy ? null : _enterSelectMode,
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                              ),
                              label: const Text('Generate SOW'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Transcripts section ───────────────────────────────────
                Expanded(
                  child:
                      transcripts.isEmpty
                          ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder_open_rounded,
                                    size: 44,
                                    color: AppColors.bodySubtle,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No transcripts yet',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Use the Record tab to capture your first scope-of-work note.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.bodyMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  OutlinedButton.icon(
                                    onPressed: widget.onGoToRecord,
                                    icon: const Icon(Icons.mic_rounded),
                                    label: const Text('Start Recording'),
                                  ),
                                ],
                              ),
                            ),
                          )
                          : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              96,
                            ),
                            itemCount: transcripts.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final transcript = transcripts[index];
                              return _TranscriptCard(
                                transcript: transcript,
                                selected:
                                    transcript.id ==
                                    controller.activeTranscriptId,
                                enabled: !isBusy,
                                formatDate: (dt) =>
                                    _formatDate(context, dt),
                                isSelecting: _isSelecting,
                                isChecked: _selectedIds.contains(
                                  transcript.id,
                                ),
                                onToggleSelect: () =>
                                    _toggleSelect(transcript.id),
                                onPreview: () =>
                                    _showPreview(context, transcript),
                                onLongPress: _isSelecting
                                    ? null
                                    : () => _toggleSelect(transcript.id),
                                onTap:
                                    _isSelecting
                                        ? () =>
                                            _toggleSelect(transcript.id)
                                        : () async {
                                          await controller.selectTranscript(
                                            transcript,
                                          );
                                          widget.onGoToRecord();
                                        },
                                onDelete: () => controller.deleteTranscript(
                                  transcript.id,
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
            // Generate SOW floating button — visible when items selected
            if (_isSelecting && widget.selectedProject != null)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                    ),
                    onPressed: () => _onGenerateSow(
                      context,
                      widget.selectedProject!,
                      transcripts,
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      'Generate SOW (${_selectedIds.length})',
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String? _formatDate(BuildContext context, DateTime? value) {
    if (value == null) return null;
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatCompactDate(value)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop top bar (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.projectCount,
    required this.selectedProject,
    required this.creatingProject,
    required this.onRefresh,
    required this.onCreateProject,
  });

  final int projectCount;
  final SowProjectModel? selectedProject;
  final bool creatingProject;
  final VoidCallback onRefresh;
  final VoidCallback onCreateProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = context.watch<AuthController>().user?.isOwner ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s4,
        AppSpacing.s5,
        AppSpacing.s4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scope of Work Transcription',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  selectedProject == null
                      ? '$projectCount project${projectCount == 1 ? '' : 's'} ready for scope capture'
                      : 'Active scope project: ${selectedProject!.name}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.bodyMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh Queue'),
          ),
          const SizedBox(width: AppSpacing.s2),
          ElevatedButton.icon(
            onPressed: creatingProject ? null : onCreateProject,
            icon:
                creatingProject
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.add_rounded),
            label: Text(creatingProject ? 'Creating...' : 'New Project'),
          ),
          const SizedBox(width: AppSpacing.s2),
          if (isOwner) ...[
            const CreditsBadge(),
            const SizedBox(width: AppSpacing.s2),
          ],
          _UserMenuButton(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Project Dialog (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog({
    required this.nameController,
    required this.clientController,
    required this.siteController,
    required this.scopeController,
    required this.notesController,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController clientController;
  final TextEditingController siteController;
  final TextEditingController scopeController;
  final TextEditingController notesController;
  final VoidCallback onSubmit;

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  String? _validationError;

  void _handleSubmit() {
    final name = widget.nameController.text.trim();
    final client = widget.clientController.text.trim();
    if (name.isEmpty || client.isEmpty) {
      setState(() => _validationError = 'Project name and client name are required.');
      return;
    }
    // Kick off background creation and close the dialog immediately.
    widget.onSubmit();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create scope project', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  'Set up the project details, then start capturing scope-of-work notes.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.s4),
                TextField(
                  controller: widget.nameController,
                  textInputAction: TextInputAction.next,
                  decoration: AppInputs.standard(labelText: 'Project name *'),
                ),
                const SizedBox(height: AppSpacing.s2),
                TextField(
                  controller: widget.clientController,
                  textInputAction: TextInputAction.next,
                  decoration: AppInputs.standard(labelText: 'Client name *'),
                ),
                const SizedBox(height: AppSpacing.s2),
                TextField(
                  controller: widget.siteController,
                  textInputAction: TextInputAction.next,
                  decoration: AppInputs.standard(labelText: 'Site location'),
                ),
                const SizedBox(height: AppSpacing.s2),
                TextField(
                  controller: widget.scopeController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: AppInputs.multiline(
                    labelText: 'Scope summary',
                    hintText: 'Briefly describe the work to capture',
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                TextField(
                  controller: widget.notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: AppInputs.multiline(
                    labelText: 'Notes',
                    hintText: 'Optional project notes or constraints',
                  ),
                ),
                if (_validationError != null) ...[  
                  const SizedBox(height: AppSpacing.s3),
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 14, color: AppColors.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _validationError!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _handleSubmit,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create project'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create template dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CreateTemplateDialog extends StatefulWidget {
  const _CreateTemplateDialog({
    required this.nameController,
    required this.contentController,
  });

  final TextEditingController nameController;
  final TextEditingController contentController;

  @override
  State<_CreateTemplateDialog> createState() => _CreateTemplateDialogState();
}

class _CreateTemplateDialogState extends State<_CreateTemplateDialog> {
  String? _validationError;

  void _handleSubmit() {
    if (widget.nameController.text.trim().isEmpty) {
      setState(() => _validationError = 'Template name is required.');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s5,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radiusSm)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New Template',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                'Create a reusable SOW text template.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.bodyMuted),
              ),
              const SizedBox(height: AppSpacing.s4),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.s4),
              TextField(
                controller: widget.nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: AppInputs.standard(
                  labelText: 'Template name *',
                  hintText: 'e.g. "Residential Renovation"',
                ),
                onChanged: (_) {
                  if (_validationError != null) {
                    setState(() => _validationError = null);
                  }
                },
              ),
              if (_validationError != null) ...[  
                const SizedBox(height: AppSpacing.s2),
                Text(
                  _validationError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: AppSpacing.s3),
              TextField(
                controller: widget.contentController,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                decoration: AppInputs.standard(
                  labelText: 'Template content',
                  hintText:
                      'Paste or type the SOW sections and structure here…',
                ).copyWith(alignLabelWithHint: true),
              ),
              const SizedBox(height: AppSpacing.s5),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _handleSubmit,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create template'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Small panel error widgets ─────────────────────────────────────────────────

class _SessionExpiredPanel extends StatelessWidget {
  const _SessionExpiredPanel({required this.onAction});
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 48,
                color: AppColors.charcoal400),
            const SizedBox(height: 12),
            const Text(
              'The editor session was lost on refresh.\n'
              'Re-open the document to continue editing.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: const Text('Back to document')),
          ],
        ),
      ),
    );
  }
}

class _DocNotFoundPanel extends StatelessWidget {
  const _DocNotFoundPanel({required this.onAction});
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48,
                color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'Could not load the document.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: onAction, child: const Text('Back to project')),
          ],
        ),
      ),
    );
  }
}

// Desktop Sidebar Panel (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarPanel extends StatefulWidget {
  const _SidebarPanel({
    required this.loading,
    required this.errorMessage,
    required this.searchController,
    required this.onSearchChanged,
    required this.projects,
    required this.selectedProjectId,
    required this.onCreateProjectTap,
    required this.onSelectProject,
    required this.templates,
    required this.pdfTemplates,
    required this.templatesLoading,
    required this.onOpenTemplate,
    required this.onDeleteTemplate,
    required this.onUsePdfTemplate,
    required this.onDeletePdfTemplate,
    required this.onCreateTemplate,
    this.embedded = false,
  });

  final bool loading;
  final String? errorMessage;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final List<SowProjectModel> projects;
  final String? selectedProjectId;
  final VoidCallback onCreateProjectTap;
  final Future<void> Function(SowProjectModel project) onSelectProject;
  final List<SowTemplateModel> templates;
  final List<Map<String, dynamic>> pdfTemplates;
  final bool templatesLoading;
  final void Function(SowTemplateModel template) onOpenTemplate;
  final void Function(String templateId) onDeleteTemplate;
  final void Function(Map<String, dynamic> template) onUsePdfTemplate;
  final void Function(String templateId) onDeletePdfTemplate;
  final VoidCallback onCreateTemplate;
  final bool embedded;

  @override
  State<_SidebarPanel> createState() => _SidebarPanelState();
}

class _SidebarPanelState extends State<_SidebarPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _countBadge(String text, ThemeData theme) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: theme.textTheme.labelSmall),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalTemplates =
        widget.templates.length + widget.pdfTemplates.length;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4, AppSpacing.s4, AppSpacing.s4, AppSpacing.s3),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.blue100,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
                child: const Icon(
                  Icons.subject_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scope Projects',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 1),
                    Text(
                      'Projects and reusable templates.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Tab bar ─────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.bodyMuted,
            labelStyle: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            unselectedLabelStyle: theme.textTheme.labelMedium,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_rounded, size: 14),
                    const SizedBox(width: 5),
                    const Text('Projects'),
                    const SizedBox(width: 5),
                    _countBadge(
                        '${widget.projects.length}', theme),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bookmark_rounded, size: 14),
                    const SizedBox(width: 5),
                    const Text('Templates'),
                    const SizedBox(width: 5),
                    widget.templatesLoading
                        ? const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5),
                          )
                        : _countBadge(
                            '$totalTemplates', theme),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Tab views ───────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Projects tab
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: widget.searchController,
                      onChanged: (_) => widget.onSearchChanged(),
                      decoration:
                          AppInputs.search(hintText: 'Search projects'),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onCreateProjectTap,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Project'),
                      ),
                    ),
                    if (widget.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.s3),
                      _InlineMessage(
                          message: widget.errorMessage!, isError: true),
                    ],
                    const SizedBox(height: AppSpacing.s4),
                    Row(
                      children: [
                        Text('Saved projects',
                            style: theme.textTheme.titleSmall),
                        const Spacer(),
                        _countBadge(
                            '${widget.projects.length}', theme),
                      ],
                    ),
                    if (widget.loading && widget.projects.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s2),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: AppSpacing.s3),
                    if (widget.loading && widget.projects.isEmpty)
                      const Center(child: CircularProgressIndicator())
                    else if (widget.projects.isEmpty)
                      _EmptyProjectsState(
                          onCreateProjectTap:
                              widget.onCreateProjectTap)
                    else
                      Column(
                        children: widget.projects
                            .map((project) {
                              final selected =
                                  project.id == widget.selectedProjectId;
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.s1),
                                child: _ProjectListTile(
                                  project: project,
                                  selected: selected,
                                  onTap: () =>
                                      widget.onSelectProject(project),
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                  ],
                ),
              ),
              // Templates tab
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onCreateTemplate,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Template'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    if (widget.templatesLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (widget.templates.isEmpty &&
                        widget.pdfTemplates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s3),
                        child: Text(
                          'No templates yet. Tap "New Template" to create one, or save a PDF layout from the PDF editor.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.bodyMuted),
                        ),
                      )
                    else ...[
                      if (widget.templates.isNotEmpty) ...[
                        Text('SOW Templates',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.s3),
                        ...widget.templates.map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppSpacing.s2),
                            child: _TemplateTile(
                              template: t,
                              onOpen: () => widget.onOpenTemplate(t),
                              onDelete: () =>
                                  widget.onDeleteTemplate(t.id),
                            ),
                          ),
                        ),
                      ],
                      if (widget.pdfTemplates.isNotEmpty) ...[
                        if (widget.templates.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: AppSpacing.s3),
                            child: Divider(height: 1),
                          ),
                        Text('PDF Layout Templates',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.s3),
                        ...widget.pdfTemplates.map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppSpacing.s2),
                            child: _PdfTemplateTile(
                              template: t,
                              onUse: () => widget.onUsePdfTemplate(t),
                              onDelete: () => widget.onDeletePdfTemplate(
                                  t['id']?.toString() ?? ''),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return content;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius2xl),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: AppShadows.card,
      ),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared / reused widgets (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final SowProjectModel project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue50 : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
          boxShadow: selected ? null : AppShadows.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.body,
                    ),
                  ),
                  if (project.clientName.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      project.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.bodyMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            _StatusChip(status: project.statusLabel),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isActive =
        status.toLowerCase() == 'active' ||
        status.toLowerCase() == 'in progress';
    final color = isActive ? AppColors.success : AppColors.primary;
    final background = isActive ? AppColors.successLight : AppColors.blue100;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.onOpen,
    required this.onDelete,
  });

  final SowTemplateModel template;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s1,
        ),
        leading: const Icon(
          Icons.bookmark_rounded,
          color: AppColors.primary,
          size: 20,
        ),
        title: Text(
          template.name,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${template.content.length} chars',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.bodyMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onOpen,
              child: const Text('Use'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.danger,
              tooltip: 'Delete template',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfTemplateTile extends StatelessWidget {
  const _PdfTemplateTile({
    required this.template,
    required this.onUse,
    required this.onDelete,
  });

  final Map<String, dynamic> template;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (template['name'] as String?)?.trim().isNotEmpty == true
        ? template['name'] as String
        : 'Untitled PDF Template';
    final pdfJson = template['pdfJson'];
    final elementCount = pdfJson is Map<String, dynamic> &&
            pdfJson['elements'] is List
        ? (pdfJson['elements'] as List).length
        : 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s1,
        ),
        leading: const Icon(
          Icons.picture_as_pdf_rounded,
          color: AppColors.danger,
          size: 20,
        ),
        title: Text(
          name,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$elementCount element${elementCount == 1 ? '' : 's'} \u00b7 PDF layout',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.bodyMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onUse,
              child: const Text('Use'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.danger,
              tooltip: 'Delete PDF template',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjectsState extends StatelessWidget {
  const _EmptyProjectsState({required this.onCreateProjectTap});

  final VoidCallback onCreateProjectTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_rounded,
            size: 44,
            color: AppColors.bodySubtle,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text('No projects yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Create the first project to begin scope-of-work transcription.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          OutlinedButton(
            onPressed: onCreateProjectTap,
            child: const Text('Create project'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop workspace (unchanged — used only on tablet/desktop)
// ─────────────────────────────────────────────────────────────────────────────

class _MainWorkspacePanel extends StatelessWidget {
  const _MainWorkspacePanel({
    super.key,
    required this.selectedProject,
    required this.transcripts,
    required this.onProjectChanged,
    required this.backendService,
    this.embedded = false,
  });

  final SowProjectModel? selectedProject;
  final List<SowTranscriptModel> transcripts;
  final Future<void> Function() onProjectChanged;
  final SowBackendService backendService;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (selectedProject == null) {
      return _BlankWorkspace(embedded: embedded);
    }

    return MultiProvider(
      providers: [
        Provider<GeminiLiveService>(
          create: (_) => createGeminiLiveService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<SowBackendService>.value(value: backendService),
        Provider<SowSharedPrefsService>(create: (_) => SowSharedPrefsService()),
        ChangeNotifierProvider<SowRecordingController>(
          key: ValueKey<String>(selectedProject!.id),
          create:
              (context) =>
                  SowRecordingController(
                      projectId: selectedProject!.id,
                      createdBy: context.read<AuthController>().user?.uid ?? '',
                      sowBackendService: context.read<SowBackendService>(),
                      geminiLiveService: context.read<GeminiLiveService>(),
                      sharedPrefsService: context.read<SowSharedPrefsService>(),
                      onAutosaveCompleted: onProjectChanged,
                    )
                    ..loadHistory(selectedProject!.id)
                    ..restoreAutosavedDraft(),
        ),
      ],
      child: _WorkspaceContent(
        project: selectedProject!,
        transcripts: transcripts,
        onProjectChanged: onProjectChanged,
        embedded: embedded,
      ),
    );
  }
}

class _BlankWorkspace extends StatelessWidget {
  const _BlankWorkspace({this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.dashboard_rounded,
                size: 52,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Pick or create a scope project',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'Select a project from the left or create a new one to start scope-of-work transcription.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.bodyMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) return body;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius2xl),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: AppShadows.card,
      ),
      child: body,
    );
  }
}

class _WorkspaceContent extends StatefulWidget {
  const _WorkspaceContent({
    required this.project,
    required this.transcripts,
    required this.onProjectChanged,
    this.embedded = false,
  });

  final SowProjectModel project;
  final List<SowTranscriptModel> transcripts;
  final Future<void> Function() onProjectChanged;
  final bool embedded;

  @override
  State<_WorkspaceContent> createState() => _WorkspaceContentState();
}

class _WorkspaceContentState extends State<_WorkspaceContent> {
  String? _lastErrorMessage;
  final TextEditingController _draftController = TextEditingController();
  bool _suppressDraftCallback = false;

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<SowRecordingController>(
      builder: (context, controller, _) {
        _handleError(context, controller);
        _syncDraftFromController(controller);

        final isConnecting =
            controller.recordingState == RecordingState.connecting;
        final isRecording =
            controller.recordingState == RecordingState.recording;
        final isSaving = controller.recordingState == RecordingState.saving;
        final isBusy = isConnecting || isSaving;
        final transcriptItems =
            controller.history.isNotEmpty
                ? controller.history
                : widget.transcripts;

        // ── Project header ──────────────────────────────────────
        final header = Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s6,
            AppSpacing.s3,
            AppSpacing.s6,
            AppSpacing.s3,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surfaceRaised,
            border: Border(
              bottom: BorderSide(color: AppColors.borderStrong),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.project.name,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.s1),
                        Text(
                          '${widget.project.clientName} – ${widget.project.siteLocation.isEmpty ? 'No site yet' : widget.project.siteLocation}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  _StatusChip(status: widget.project.statusLabel),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Wrap(
                spacing: AppSpacing.s3,
                runSpacing: AppSpacing.s3,
                children: [
                  _MetricCard(
                    label: 'Transcripts',
                    value: '${widget.project.transcriptCount}',
                  ),
                  _MetricCard(
                    label: 'Recording time',
                    value: widget.project.totalDurationLabel,
                  ),
                  _MetricCard(
                    label: 'Last activity',
                    value:
                        _formatDate(widget.project.lastTranscriptAt) ??
                        'No transcripts yet',
                  ),
                ],
              ),
              if (widget.project.scopeSummary.isNotEmpty ||
                  widget.project.notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s4),
                _ProjectInsightCard(project: widget.project),
              ],
            ],
          ),
        );

        // ── Workspace ───────────────────────────────────────────
        final workspace = Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s5),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final selector = _WorkspaceSidePanel(
                  project: widget.project,
                  transcripts: transcriptItems,
                  activeTranscriptId: controller.activeTranscriptId,
                  hasUnsavedDraft:
                      controller.hasDraft &&
                      controller.activeTranscriptId == null,
                  isBusy: isRecording || isBusy,
                  onCreateNew: controller.resetDraft,
                  onSelect: controller.selectTranscript,
                  onDelete: (id) {
                    unawaited(controller.deleteTranscript(id));
                    unawaited(widget.onProjectChanged());
                  },
                  formatDate: _formatDate,
                );
                final editor = _TranscriptPanel(
                  controller: controller,
                  draftController: _draftController,
                  isRecording: isRecording,
                  isSaving: isSaving,
                  onDraftChanged: (value) {
                    if (_suppressDraftCallback) return;
                    controller.updateDraft(value);
                  },
                  onResync: controller.resyncDraft,
                  onReset: controller.resetDraft,
                  onSave: () async {
                    await controller.saveDraft();
                    if (!mounted) return;
                    // Refresh project metadata in the background — don't block the UI.
                    unawaited(widget.onProjectChanged());
                  },
                  onToggleRecording: _toggleRecording,
                );

                final useStackedWorkspace = constraints.maxWidth < 1080;
                final inner = useStackedWorkspace
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: editor),
                          const SizedBox(height: AppSpacing.s4),
                          SizedBox(height: 360, child: selector),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: editor),
                          const SizedBox(width: AppSpacing.s4),
                          SizedBox(width: 320, child: selector),
                        ],
                      );

                // Cap content width to prevent excessive stretching on wide screens.
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 1160,
                      minHeight: constraints.maxHeight,
                      maxHeight: constraints.maxHeight,
                    ),
                    child: inner,
                  ),
                );
              },
            ),
          ),
        );

        final body = ProjectPermissionScope.load(
          projectId: widget.project.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, workspace],
          ),
        );

        if (widget.embedded) return body;

        return Container(
          width: double.infinity,
          color: AppColors.surface,
          child: body,
        );
      },
    );
  }

  Future<void> _toggleRecording(
    BuildContext context,
    SowRecordingController controller,
  ) async {
    if (controller.recordingState == RecordingState.recording) {
      await controller.stopRecording();
      return;
    }
    // Permission gate (owners/guests always pass).
    final auth = context.read<AuthController>();
    final perm = await auth.permissionsForProject(widget.project.id);
    if (!perm.canRecord) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You don't have permission to record on this project.",
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    await controller.startRecording();
  }

  void _syncDraftFromController(SowRecordingController controller) {
    if (_draftController.text == controller.draftTranscript) return;
    _suppressDraftCallback = true;
    _draftController.value = TextEditingValue(
      text: controller.draftTranscript,
      selection: TextSelection.collapsed(
        offset: controller.draftTranscript.length,
      ),
    );
    _suppressDraftCallback = false;
  }

  void _handleError(BuildContext context, SowRecordingController controller) {
    final message = controller.errorMessage;
    if (message == null || message == _lastErrorMessage) return;
    _lastErrorMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text(message)),
      );
      context.read<SowRecordingController>().clearError();
    });
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatCompactDate(value)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }
}

class _TranscriptSelectorSection extends StatefulWidget {
  const _TranscriptSelectorSection({
    required this.project,
    required this.transcripts,
    required this.activeTranscriptId,
    required this.hasUnsavedDraft,
    required this.isBusy,
    required this.onCreateNew,
    required this.onSelect,
    required this.onDelete,
    required this.formatDate,
    required this.onSowGenerated,
  });

  final List<SowTranscriptModel> transcripts;
  final String? activeTranscriptId;
  final bool hasUnsavedDraft;
  final bool isBusy;
  final VoidCallback onCreateNew;
  final ValueChanged<SowTranscriptModel> onSelect;
  final ValueChanged<String> onDelete;
  final String? Function(DateTime? value) formatDate;
  final SowProjectModel project;
  final VoidCallback onSowGenerated;

  @override
  State<_TranscriptSelectorSection> createState() =>
      _TranscriptSelectorSectionState();
}

class _TranscriptSelectorSectionState
    extends State<_TranscriptSelectorSection> {
  final ScrollController _scrollController = ScrollController();

  final Set<String> _selectedIds = {};
  bool _selectMode = false;

  bool get _isSelecting => _selectMode || _selectedIds.isNotEmpty;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  void _clearSelection() => setState(() {
    _selectedIds.clear();
    _selectMode = false;
  });

  Future<void> _onGenerateSow() async {
    if (_selectedIds.isEmpty) return;
    final backendService = context.read<SowBackendService>();
    final sharedPrefsService = context.read<SowSharedPrefsService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final selectedTranscriptIds = _selectedIds.toList();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating SOW…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final settings = await sharedPrefsService.loadSowSettings();

    try {
      final sow = await backendService.generateSow(
        projectId: widget.project.id,
        transcriptIds: selectedTranscriptIds,
        settings: settings,
      );
      navigator.pop();
      if (!context.mounted) return;
      _clearSelection();
      await SowDocumentScreen.show(
        context,
        projectName: widget.project.name,
        content: sow,
        clientName: widget.project.clientName,
        siteLocation: widget.project.siteLocation,
        scopeSummary: widget.project.scopeSummary,
        projectId: widget.project.id,
        transcriptIds: selectedTranscriptIds,
        frameUrls: widget.transcripts
            .where((t) => _selectedIds.contains(t.id))
            .expand((t) => t.frameUrls)
            .toList(),
        backendService: backendService,
      );
      widget.onSowGenerated();
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to generate SOW: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top bar — selection mode vs normal ────────────
              if (_isSelecting)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: const BoxDecoration(
                    color: AppColors.blue100,
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderStrong),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_selectedIds.length} selected',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedIds.length ==
                                widget.transcripts.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds.addAll(
                                widget.transcripts.map((t) => t.id),
                              );
                            }
                          });
                        },
                        child: Text(
                          _selectedIds.length == widget.transcripts.length
                              ? 'Deselect all'
                              : 'Select all',
                        ),
                      ),
                      TextButton(
                        onPressed: _clearSelection,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                )
              else ...[
                // ── Draft banner ─────────────────────────────────
                if (widget.hasUnsavedDraft)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: 10,
                    ),
                    color: AppColors.blue100,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Unsaved draft is active.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // ── Action buttons ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s4,
                    AppSpacing.s3,
                    AppSpacing.s4,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed:
                              widget.isBusy ? null : widget.onCreateNew,
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('Start New Transcript'),
                        ),
                      ),
                      if (widget.transcripts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 44,
                          child: FilledButton.icon(
                            onPressed: widget.isBusy
                                ? null
                                : () => setState(() => _selectMode = true),
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: const Text('Generate SOW'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s3),
              // ── Transcript list ───────────────────────────────
              Expanded(
                child: widget.transcripts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.s4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Create the first scope transcript',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              'Use Start Recording to capture a new note.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.bodyMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        controller: _scrollController,
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.s4, 0, AppSpacing.s4, 80,
                          ),
                          itemCount: widget.transcripts.length,
                          itemBuilder: (context, index) {
                            final transcript = widget.transcripts[index];
                            return _TranscriptCard(
                              transcript: transcript,
                              selected:
                                  transcript.id == widget.activeTranscriptId,
                              enabled: !widget.isBusy,
                              formatDate: widget.formatDate,
                              isSelecting: _isSelecting,
                              isChecked:
                                  _selectedIds.contains(transcript.id),
                              onToggleSelect: () =>
                                  _toggleSelect(transcript.id),
                              onTap: _isSelecting
                                  ? () => _toggleSelect(transcript.id)
                                  : () => widget.onSelect(transcript),
                              onLongPress: _isSelecting
                                  ? null
                                  : () => _toggleSelect(transcript.id),
                              onDelete: () => widget.onDelete(transcript.id),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.s3),
                        ),
                      ),
              ),
            ],
          ),
          // ── Floating Generate SOW button ──────────────────────
          if (_isSelecting)
            Positioned(
              bottom: 12,
              left: AppSpacing.s4,
              right: AppSpacing.s4,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    elevation: 4,
                  ),
                  onPressed:
                      widget.isBusy || _selectedIds.isEmpty
                          ? null
                          : _onGenerateSow,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text('Generate SOW (${_selectedIds.length})'),
                ),
              ),
            ),
        ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Documents panel — Saved SOWs + standalone PDF documents (shared mobile + web)
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentsPanel extends StatefulWidget {
  const _DocumentsPanel({
    required this.project,
    this.reload,
  });

  final SowProjectModel project;

  /// Bumping this notifier triggers a reload of the documents lists.
  final Listenable? reload;

  @override
  State<_DocumentsPanel> createState() => _DocumentsPanelState();
}

class _DocumentsPanelState extends State<_DocumentsPanel> {
  List<SowDocumentModel> _savedSows = [];
  bool _sowsLoading = false;

  List<PdfDocumentModel> _pdfDocuments = [];
  bool _pdfDocsLoading = false;

  @override
  void initState() {
    super.initState();
    widget.reload?.addListener(_reload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedSows();
      _loadPdfDocuments();
    });
  }

  @override
  void didUpdateWidget(_DocumentsPanel old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload?.removeListener(_reload);
      widget.reload?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.reload?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    _loadSavedSows();
    _loadPdfDocuments();
  }

  Future<void> _loadSavedSows() async {
    if (!mounted) return;
    final service = context.read<SowBackendService>();
    setState(() => _sowsLoading = true);
    try {
      final docs = await service.fetchSowDocuments(widget.project.id);
      if (mounted) setState(() => _savedSows = docs);
    } catch (_) {
      // Non-fatal: silently ignore
    } finally {
      if (mounted) setState(() => _sowsLoading = false);
    }
  }

  Future<void> _loadPdfDocuments() async {
    if (!mounted) return;
    final service = context.read<SowBackendService>();
    setState(() => _pdfDocsLoading = true);
    try {
      final docs = await service.fetchPdfDocuments(widget.project.id);
      if (mounted) setState(() => _pdfDocuments = docs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _pdfDocsLoading = false);
    }
  }

  Future<void> _deleteSow(String id) async {
    final service = context.read<SowBackendService>();
    try {
      await service.deleteSowDocument(widget.project.id, id);
      if (mounted) setState(() => _savedSows.removeWhere((d) => d.id == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deletePdf(String id) async {
    final service = context.read<SowBackendService>();
    try {
      await service.deletePdfDocument(widget.project.id, id);
      if (mounted) setState(() => _pdfDocuments.removeWhere((d) => d.id == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // ── Saved SOWs ────────────────────────────────────────────────────
        Row(
          children: [
            const Icon(
              Icons.description_rounded,
              size: 16,
              color: AppColors.bodyMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'Saved SOWs',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.bodyMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_sowsLoading)
          const LinearProgressIndicator()
        else if (_savedSows.isEmpty)
          Text(
            'No saved SOWs yet. Generate one from the Transcripts tab.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.bodyMuted,
            ),
          )
        else
          ..._savedSows.map(
            (sowDoc) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SowDocumentCard(
                document: sowDoc,
                expand: true,
                onView: () async {
                  await SowDocumentScreen.show(
                    context,
                    projectName: widget.project.name,
                    content: sowDoc.content,
                    clientName: widget.project.clientName,
                    siteLocation: widget.project.siteLocation,
                    scopeSummary: widget.project.scopeSummary,
                    projectId: sowDoc.projectId,
                    documentId: sowDoc.id,
                    transcriptIds: sowDoc.transcriptIds,
                    frameUrls: sowDoc.frameUrls,
                    backendService: context.read<SowBackendService>(),
                  );
                  _loadSavedSows();
                },
                onDelete: () => _deleteSow(sowDoc.id),
              ),
            ),
          ),
        const SizedBox(height: 24),
        // ── PDF Documents ─────────────────────────────────────────────────
        Row(
          children: [
            const Icon(
              Icons.picture_as_pdf_rounded,
              size: 16,
              color: AppColors.bodyMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'PDF Documents',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.bodyMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 30,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: theme.textTheme.labelSmall,
                ),
                onPressed: () =>
                    context.go('/project/${widget.project.id}/pdf/new'),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: const Text('New PDF'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_pdfDocsLoading)
          const LinearProgressIndicator()
        else if (_pdfDocuments.isEmpty)
          Text(
            'No PDFs yet. Tap New PDF to create one.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.bodyMuted,
            ),
          )
        else
          ..._pdfDocuments.map(
            (pdfDoc) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PdfDocumentCard(
                document: pdfDoc,
                expand: true,
                onOpen: () => context.go(
                  '/project/${widget.project.id}/pdf/${pdfDoc.id}',
                ),
                onDelete: () => _deletePdf(pdfDoc.id),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop workspace side panel — History / Documents tabs (mirrors mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _WorkspaceSidePanel extends StatefulWidget {
  const _WorkspaceSidePanel({
    required this.project,
    required this.transcripts,
    required this.activeTranscriptId,
    required this.hasUnsavedDraft,
    required this.isBusy,
    required this.onCreateNew,
    required this.onSelect,
    required this.onDelete,
    required this.formatDate,
  });

  final SowProjectModel project;
  final List<SowTranscriptModel> transcripts;
  final String? activeTranscriptId;
  final bool hasUnsavedDraft;
  final bool isBusy;
  final VoidCallback onCreateNew;
  final ValueChanged<SowTranscriptModel> onSelect;
  final ValueChanged<String> onDelete;
  final String? Function(DateTime? value) formatDate;

  @override
  State<_WorkspaceSidePanel> createState() => _WorkspaceSidePanelState();
}

class _WorkspaceSidePanelState extends State<_WorkspaceSidePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this)..addListener(_onTabChanged);
  final ValueNotifier<int> _docsReload = ValueNotifier<int>(0);

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    // Refresh documents whenever the Documents tab becomes active.
    if (_tabController.index == 1) _docsReload.value++;
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _docsReload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.surfaceRaised,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.history_rounded, size: 16),
                  text: 'History',
                ),
                Tab(
                  icon: Icon(Icons.folder_open_rounded, size: 16),
                  text: 'Documents',
                ),
              ],
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.bodyMuted,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _TranscriptSelectorSection(
                  project: widget.project,
                  transcripts: widget.transcripts,
                  activeTranscriptId: widget.activeTranscriptId,
                  hasUnsavedDraft: widget.hasUnsavedDraft,
                  isBusy: widget.isBusy,
                  onCreateNew: widget.onCreateNew,
                  onSelect: widget.onSelect,
                  onDelete: widget.onDelete,
                  formatDate: widget.formatDate,
                  onSowGenerated: () => _docsReload.value++,
                ),
                _DocumentsPanel(
                  project: widget.project,
                  reload: _docsReload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved SOW document compact card (horizontal scroll)
// ─────────────────────────────────────────────────────────────────────────────

class _SowDocumentCard extends StatelessWidget {
  const _SowDocumentCard({
    required this.document,
    required this.onView,
    required this.onDelete,
    this.expand = false,
  });

  final SowDocumentModel document;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: expand ? null : 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (document.updatedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    MaterialLocalizations.of(context)
                        .formatCompactDate(document.updatedAt!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.bodyMuted),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      height: 26,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: theme.textTheme.labelSmall,
                        ),
                        onPressed: onView,
                        child: const Text('View'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (ProjectPermissionScope.of(context).canEditDocument)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.bodyMuted,
              tooltip: 'Delete',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _PdfDocumentCard extends StatelessWidget {
  const _PdfDocumentCard({
    required this.document,
    required this.onOpen,
    required this.onDelete,
    this.expand = false,
  });

  final PdfDocumentModel document;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: expand ? null : 200,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 13,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (document.updatedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    MaterialLocalizations.of(context)
                        .formatCompactDate(document.updatedAt!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.bodyMuted),
                  ),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  height: 26,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: theme.textTheme.labelSmall,
                    ),
                    onPressed: onOpen,
                    child: const Text('Open'),
                  ),
                ),
              ],
            ),
          ),
          if (ProjectPermissionScope.of(context).canEditDocument)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.bodyMuted,
              tooltip: 'Delete',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.transcript,
    required this.selected,
    required this.enabled,
    required this.formatDate,
    required this.onTap,
    required this.onDelete,
    this.onPreview,
    this.onLongPress,
    this.isSelecting = false,
    this.isChecked = false,
    this.onToggleSelect,
  });

  final SowTranscriptModel transcript;
  final bool selected;
  final bool enabled;
  final String? Function(DateTime? value) formatDate;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onPreview;
  final VoidCallback? onLongPress;
  final bool isSelecting;
  final bool isChecked;
  final VoidCallback? onToggleSelect;

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Transcript?'),
            content: const Text(
              'This action cannot be undone and you will lose this recording.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.surface,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stamp =
        formatDate(transcript.updatedAt ?? transcript.createdAt) ?? 'Unknown';
    final displayTitle =
        transcript.title?.trim().isNotEmpty == true
            ? transcript.title!.trim()
            : stamp;
    final hasCustomTitle = transcript.title?.trim().isNotEmpty == true;

    return InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
        decoration: BoxDecoration(
          color:
              isChecked || selected ? AppColors.blue50 : AppColors.surface,
          border: Border.all(
            color:
                isChecked || selected
                    ? AppColors.primary
                    : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: checkbox? + title + duration + preview + delete
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isSelecting)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isChecked,
                        onChanged:
                            enabled
                                ? (_) => onToggleSelect?.call()
                                : null,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    displayTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _durationLabel(transcript.durationSeconds),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.bodyMuted,
                  ),
                ),
                if (onPreview != null)
                  IconButton(
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 18,
                    ),
                    color: AppColors.bodyMuted,
                    tooltip: 'Preview',
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? onPreview : null,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.danger,
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled &&
                          ProjectPermissionScope.of(context)
                              .canDeleteTranscript
                      ? () => _handleDelete(context)
                      : null,
                ),
              ],
            ),
            // Timestamp — only shown separately when a custom title is set
            if (hasCustomTitle) ...[
              const SizedBox(height: 2),
              Text(
                stamp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.bodyMuted,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s2),
            Text(
              transcript.rawTranscript,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            // Frame thumbnails (video sessions only)
            if (transcript.frameUrls.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s3),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: transcript.frameUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: Image.network(
                      transcript.frameUrls[i],
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: AppColors.surfaceRaised,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 20,
                          color: AppColors.bodyMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _durationLabel(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transcript preview bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TranscriptPreviewSheet extends StatelessWidget {
  const _TranscriptPreviewSheet({required this.transcript});

  final SowTranscriptModel transcript;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transcript.title?.trim().isNotEmpty == true
                              ? transcript.title!.trim()
                              : 'Transcript',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _durationLabel(transcript.durationSeconds),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Frame thumbnails (larger view)
                  if (transcript.frameUrls.isNotEmpty) ...[
                    Text(
                      'Captured Frames',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: transcript.frameUrls.length,
                        separatorBuilder:
                            (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          child: Image.network(
                            transcript.frameUrls[i],
                            width: 160,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 160,
                              height: 120,
                              color: AppColors.surfaceRaised,
                              child: const Icon(
                                Icons.broken_image_outlined,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // Full transcript text
                  Text('Transcript', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SelectableText(
                    transcript.rawTranscript.trim().isEmpty
                        ? '(no transcript text)'
                        : transcript.rawTranscript.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _durationLabel(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}

class _ProjectInsightCard extends StatelessWidget {
  const _ProjectInsightCard({required this.project});

  final SowProjectModel project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: AppSpacing.s4,
        runSpacing: AppSpacing.s3,
        children: [
          if (project.scopeSummary.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scope summary', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.s1),
                  Text(project.scopeSummary, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (project.notes.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.s1),
                  Text(project.notes, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({
    required this.controller,
    required this.draftController,
    required this.isRecording,
    required this.isSaving,
    required this.onDraftChanged,
    required this.onResync,
    required this.onReset,
    required this.onSave,
    required this.onToggleRecording,
  });

  final SowRecordingController controller;
  final TextEditingController draftController;
  final bool isRecording;
  final bool isSaving;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onResync;
  final VoidCallback onReset;
  final Future<void> Function() onSave;
  final Future<void> Function(
    BuildContext context,
    SowRecordingController controller,
  )
  onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResync =
        !isSaving && (controller.hasPendingResync || controller.hasLocalEdits);
    final canReset = !isSaving && controller.draftTranscript.trim().isNotEmpty;
    final canSave = !isSaving && controller.draftTranscript.trim().isNotEmpty;
    final transcriptModeLabel =
        controller.activeTranscriptId == null
            ? 'New transcript draft'
            : 'Saved transcript loaded';
    final draftStatusMessage =
        controller.hasPendingResync
            ? 'New speech detected. Tap resync to merge it with your edits.'
            : controller.hasLocalEdits
            ? 'Draft edited locally. Save it when the wording looks right.'
            : controller.hasDraft
            ? 'The next recording will append to this draft.'
            : 'The next recording will start a new transcript.';

    Widget buildActionButtons() {
      return Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          OutlinedButton.icon(
            onPressed: canReset ? onReset : null,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Reset Draft'),
          ),
          OutlinedButton.icon(
            onPressed: canResync ? onResync : null,
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Resync'),
          ),
          ElevatedButton.icon(
            onPressed: canSave ? onSave : null,
            icon: const Icon(Icons.save_rounded),
            label: Text(controller.saveActionLabel),
          ),
        ],
      );
    }

    Widget buildDraftTextField() {
      return TextField(
        controller: draftController,
        onChanged: onDraftChanged,
        minLines: null,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: AppInputs.multiline(
          labelText: 'Transcript draft',
          hintText:
              'Live transcript appears here. Edit any words before saving.',
          fillColor: AppColors.surface,
        ),
      );
    }

    Widget buildActionSection(BoxConstraints constraints) {
      final compact = constraints.maxWidth < 900;
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(draftStatusMessage, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.s2),
            buildActionButtons(),
          ],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(draftStatusMessage, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: AppSpacing.s2),
          Flexible(
            child: Align(
              alignment: Alignment.topRight,
              child: buildActionButtons(),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = <Widget>[
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Scope transcript editor',
                  style: theme.textTheme.titleSmall,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s1,
                  ),
                  decoration: const BoxDecoration(color: AppColors.blue100),
                  child: Text(
                    transcriptModeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (isRecording)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2,
                      vertical: AppSpacing.s1,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.dangerLight,
                    ),
                    child: Text(
                      'Recording live',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Type directly in the draft, reset it to start over, or keep recording to append more speech.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.bodyMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            if (isRecording) ...[
              RecordingStatusBar(elapsedSeconds: controller.elapsedSeconds),
              const SizedBox(height: AppSpacing.s3),
            ],
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...content,
              Expanded(child: buildDraftTextField()),
              const SizedBox(height: AppSpacing.s3),
              LayoutBuilder(
                builder: (context, rowConstraints) {
                  return buildActionSection(rowConstraints);
                },
              ),
              const SizedBox(height: AppSpacing.s3),
              Row(
                children: [
                  Expanded(
                    child: RecordingControlButton(
                      state: controller.recordingState,
                      idleLabel: controller.recordingActionLabel,
                      onPressed:
                          isSaving
                              ? null
                              : () => onToggleRecording(context, controller),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: AppColors.blue50,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.blue200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.s1),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final background = isError ? AppColors.dangerLight : AppColors.successLight;
    final color = isError ? AppColors.danger : AppColors.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User Menu Button
// ─────────────────────────────────────────────────────────────────────────────

class _UserMenuButton extends StatelessWidget {
  const _UserMenuButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;

    final initials = user?.initials ?? '?';

    return PopupMenuButton<_UserMenuAction>(
      offset: const Offset(0, 48),
      tooltip: 'Account',
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (_) => [
        PopupMenuItem<_UserMenuAction>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user?.displayName.isNotEmpty == true
                    ? user!.displayName
                    : 'Account',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (user != null)
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.bodyMuted,
                  ),
                ),
              if (user != null)
                Text(
                  user.isOwner ? 'Owner' : 'Member',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (user?.isOwner == true)
          const PopupMenuItem<_UserMenuAction>(
            value: _UserMenuAction.inviteTeam,
            child: Row(
              children: [
                Icon(Icons.group_add_outlined, size: 18),
                SizedBox(width: 8),
                Text('Invite Team'),
              ],
            ),
          ),
        if (user?.isOwner == true)
          const PopupMenuItem<_UserMenuAction>(
            value: _UserMenuAction.companySettings,
            child: Row(
              children: [
                Icon(Icons.business_outlined, size: 18),
                SizedBox(width: 8),
                Text('Company Settings'),
              ],
            ),
          ),
        if (user?.isOwner == true)
          const PopupMenuItem<_UserMenuAction>(
            value: _UserMenuAction.teamSettings,
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings_outlined, size: 18),
                SizedBox(width: 8),
                Text('Team Settings'),
              ],
            ),
          ),
        const PopupMenuItem<_UserMenuAction>(
          value: _UserMenuAction.sowSettings,
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 18),
              SizedBox(width: 8),
              Text('SOW Settings'),
            ],
          ),
        ),
        const PopupMenuItem<_UserMenuAction>(
          value: _UserMenuAction.activityLog,
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 18),
              SizedBox(width: 8),
              Text('Activity Log'),
            ],
          ),
        ),
        if (user?.isOwner == true)
          const PopupMenuItem<_UserMenuAction>(
            value: _UserMenuAction.billing,
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: AppColors.warning),
                SizedBox(width: 8),
                Text('Credits & Billing'),
              ],
            ),
          ),
        const PopupMenuItem<_UserMenuAction>(
          value: _UserMenuAction.signOut,
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Sign Out', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
      child: Container(
        width: compact ? 36 : 40,
        height: compact ? 36 : 40,
        decoration: BoxDecoration(
          color: AppColors.blue100,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, _UserMenuAction action) {
    switch (action) {
      case _UserMenuAction.inviteTeam:
        context.pushNamed(AppRoute.teamInvite.name);
      case _UserMenuAction.companySettings:
        context.pushNamed(AppRoute.companySettings.name);
      case _UserMenuAction.teamSettings:
        context.pushNamed(AppRoute.teamSettings.name);
      case _UserMenuAction.sowSettings:
        context.pushNamed(AppRoute.sowSettings.name);
      case _UserMenuAction.activityLog:
        context.pushNamed(AppRoute.activityLog.name);
      case _UserMenuAction.billing:
        context.pushNamed(AppRoute.billing.name);
      case _UserMenuAction.signOut:
        unawaited(_signOut(context));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<AuthController>().signOut();
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    }
  }
}

enum _UserMenuAction { inviteTeam, companySettings, teamSettings, sowSettings, activityLog, billing, signOut }
