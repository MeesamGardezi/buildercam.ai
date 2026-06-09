import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu, LogicalKeyboardKey, KeyEvent, KeyDownEvent;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:buildercam/core/router/app_router.dart';
import 'package:buildercam/features/auth/auth_module.dart';

import 'core/app_colors.dart';
import 'core/app_spacing.dart';
import 'core/app_theme.dart';
import 'keyboard/editor_shortcuts_handler.dart';
import 'models/pdf_document_data.dart';
import 'providers/template_editor_provider.dart';
import 'models/element_type.dart';
import 'models/template_element_model.dart';
import 'models/template_model.dart';
import 'repositories/template_repository.dart';
import 'services/pdf_export_service.dart';
import 'widgets/canvas/editor_canvas_widget.dart';
import 'widgets/panels/left_panel_layers.dart';
import 'widgets/panels/right_panel_properties.dart' show PropertiesTopBar;

/// Embeddable PDF editor widget.
///
/// Drop this anywhere in your app. The parent software supplies
/// [initialData] — no template selection screen is shown. The user
/// edits the document and can preview/download/print it.
///
/// ```dart
/// PdfEditorWidget(
///   initialData: PdfDocumentData.fromJson(myJson),
///   apiBaseUrl: 'https://api.example.com',
///   companyId: 'acme',
///   onClose: () => Navigator.pop(context),
/// )
/// ```
class PdfEditorWidget extends StatelessWidget {
  final PdfDocumentData initialData;
  final String apiBaseUrl;
  final String companyId;
  final List<String> frameUrls;

  /// Optional project id forwarded to the backend on PDF generate calls so
  /// per-project `canExport` permissions can be enforced for team members.
  final String? projectId;

  /// Called when the user taps the close/back button in the toolbar.
  /// If null, no close button is shown.
  final VoidCallback? onClose;

  /// Called when the user taps the "Save" button in the toolbar.
  /// The parent is responsible for persisting the data.
  final void Function(PdfDocumentData data)? onSave;

  /// Called whenever the editor content changes (debounced ~1 s).
  /// Use for auto-draft to local storage.
  final void Function(PdfDocumentData data)? onSnapshot;

  /// Optional Firebase ID token provider used for authenticated operations
  /// (e.g. saving PDF layouts as templates). When null, the "Save as Template"
  /// button is not shown.
  final Future<String?> Function()? tokenProvider;

  /// Called after the user successfully saves the current canvas as a
  /// company-level PDF template via the toolbar action. Lets parents refresh
  /// any visible templates list.
  final VoidCallback? onTemplateSaved;

  /// When non-null, the editor starts in "edit existing template" mode:
  /// the first "Save as Template" call will PUT to update this template
  /// instead of POSTing a new one.
  final String? initialTemplateId;

  const PdfEditorWidget({
    super.key,
    required this.initialData,
    required this.apiBaseUrl,
    this.companyId = '',
    this.frameUrls = const [],
    this.projectId,
    this.onClose,
    this.onSave,
    this.onSnapshot,
    this.tokenProvider,
    this.onTemplateSaved,
    this.initialTemplateId,
  });

  /// Convenience constructor — parent software passes raw JSON directly.
  ///
  /// ```dart
  /// PdfEditorWidget.fromJson(
  ///   json: apiResponse,   // Map<String, dynamic> from your backend
  ///   apiBaseUrl: 'https://api.example.com',
  ///   companyId: 'acme',
  ///   onClose: () => Navigator.pop(context),
  /// )
  /// ```
  factory PdfEditorWidget.fromJson({
    Key? key,
    required Map<String, dynamic> json,
    required String apiBaseUrl,
    String companyId = '',
    String? projectId,
    VoidCallback? onClose,
    Future<String?> Function()? tokenProvider,
  }) =>
      PdfEditorWidget(
        key: key,
        initialData: PdfDocumentData.fromJson(json),
        apiBaseUrl: apiBaseUrl,
        companyId: companyId,
        projectId: projectId,
        onClose: onClose,
        tokenProvider: tokenProvider,
      );

  @override
  Widget build(BuildContext context) {
    // _NoOpRepository: the module never saves to a backend — the provider's
    // auto-save calls are silently discarded instead of hitting the API.
    final repo = _NoOpRepository();
    final exportService = PdfExportService(
      baseUrl: apiBaseUrl,
      companyId: companyId,
      tokenProvider: tokenProvider,
      projectId: projectId,
    );

    return Theme(
      data: buildAppTheme(),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => TemplateEditorProvider(
              repo: repo,
              companyId: companyId,
            ),
          ),
          Provider<PdfExportService>.value(value: exportService),
        ],
        child: _withPermissionScope(
          _EditorShell(
            initialData: initialData,
            apiBaseUrl: apiBaseUrl,
            onClose: onClose,
            onSave: onSave,
            onSnapshot: onSnapshot,
            frameUrls: frameUrls,
            tokenProvider: tokenProvider,
            onTemplateSaved: onTemplateSaved,
            initialTemplateId: initialTemplateId,
          ),
        ),
      ),
    );
  }

  Widget _withPermissionScope(Widget child) {
    final pid = projectId;
    if (pid == null || pid.isEmpty) return child;
    return ProjectPermissionScope.load(projectId: pid, child: child);
  }
}

// ── Shell (stateful — owns loadFromData call) ─────────────────────────────────

class _EditorShell extends StatefulWidget {
  final PdfDocumentData initialData;
  final String apiBaseUrl;
  final VoidCallback? onClose;
  final void Function(PdfDocumentData data)? onSave;
  final void Function(PdfDocumentData data)? onSnapshot;
  final List<String> frameUrls;
  final Future<String?> Function()? tokenProvider;
  final VoidCallback? onTemplateSaved;
  final String? initialTemplateId;

  const _EditorShell({
    required this.initialData,
    required this.apiBaseUrl,
    this.onClose,
    this.onSave,
    this.onSnapshot,
    this.frameUrls = const [],
    this.tokenProvider,
    this.onTemplateSaved,
    this.initialTemplateId,
  });

  @override
  State<_EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<_EditorShell> {
  Timer? _snapshotDebounce;

  /// Non-null when the canvas is bound to an existing template (edit mode).
  /// Set from [widget.initialTemplateId] or after successfully creating a
  /// new template, so subsequent saves call PUT instead of POST.
  String? _currentTemplateId;

  @override
  void initState() {
    super.initState();
    _currentTemplateId = widget.initialTemplateId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<TemplateEditorProvider>();
      provider.loadFromData(widget.initialData);
      if (widget.onSnapshot != null) {
        provider.addListener(_onProviderChanged);
      }
    });
  }

  @override
  void dispose() {
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
    _snapshotDebounce?.cancel();
    // Remove listener — provider lives in parent's MultiProvider so it outlives
    // this state; safe to remove before it disposes.
    if (widget.onSnapshot != null && mounted) {
      try {
        context.read<TemplateEditorProvider>().removeListener(_onProviderChanged);
      } catch (_) {}
    }
    super.dispose();
  }

  void _onProviderChanged() {
    _snapshotDebounce?.cancel();
    _snapshotDebounce = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final provider = context.read<TemplateEditorProvider>();
      final snapshot = _buildSnapshot(provider);
      if (snapshot != null) widget.onSnapshot?.call(snapshot);
    });
  }

  PdfDocumentData? _buildSnapshot(TemplateEditorProvider provider) {
    final template = provider.template;
    if (template == null) return null;
    return PdfDocumentData(
      name: template.name,
      pageSize: template.pageSize,
      elements: provider.elements.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TemplateEditorProvider>(
      builder: (context, provider, _) {
        if (!provider.isLoaded) {
          return const Scaffold(
            body: SafeArea(
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return EditorShortcutsWrapper(
          onSave: () {},
          child: Scaffold(
            backgroundColor: AppColors.pageBackground,
            body: SafeArea(
              child: Column(
                children: [
                  _EmbeddedToolbar(
                  provider: provider,
                  onClose: widget.onClose,
                  onPreview: () => _openPreview(context, provider),
                  onDownload: () => _download(context, provider),
                  onPrint: () => _print(context, provider),
                  onShare: () => _share(context, provider),
                  onSaveAsTemplate: widget.tokenProvider != null
                      ? () => _saveAsTemplate(context, provider)
                      : null,
                  isTemplateUpdateMode: _currentTemplateId != null,
                  onSave: widget.onSave != null
                      ? () {
                          final snap = _buildSnapshot(provider);
                          if (snap != null) widget.onSave?.call(snap);
                        }
                      : null,
                ),
                const PropertiesTopBar(),
                Expanded(
                  child: _EditorBody(
                    provider: provider,
                    frameUrls: widget.frameUrls,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      },
    );
  }

  void _openPreview(BuildContext context, TemplateEditorProvider provider) {
    final template = provider.template;
    if (template == null) return;
    final snapshot = template.copyWith(elements: provider.elements.toList());
    final exportService = context.read<PdfExportService>();
    final canExport = ProjectPermissionScope.of(context).canExport;
    context.pushNamed(
      AppRoute.templatePreview.name,
      extra: TemplatePreviewArgs(
        template: snapshot,
        exportService: exportService,
        canExport: canExport,
      ),
    );
  }

  Future<void> _download(
      BuildContext context, TemplateEditorProvider provider) async {
    await _runExport(context, provider, mode: _ExportMode.download);
  }

  Future<void> _print(
      BuildContext context, TemplateEditorProvider provider) async {
    await _runExport(context, provider, mode: _ExportMode.print);
  }

  Future<void> _share(
      BuildContext context, TemplateEditorProvider provider) async {
    await _runExport(context, provider, mode: _ExportMode.share);
  }

  void _saveAsTemplate(
      BuildContext context, TemplateEditorProvider provider) {
    final template = provider.template;
    if (template == null) return;

    final isUpdate = _currentTemplateId != null;

    // When updating an existing template, skip the name dialog and PUT directly.
    if (isUpdate) {
      _doUpdateTemplate(context, provider, template);
      return;
    }

    // New template — prompt for a name first.
    final initialName =
        template.name.isNotEmpty ? template.name : 'My PDF Template';
    String enteredName = initialName;

    Future<void> submit(BuildContext ctx) async {
      final finalName =
          enteredName.trim().isEmpty ? 'Untitled Template' : enteredName.trim();
      if (template.name != finalName) provider.renameTemplate(finalName);
      final snapshot =
          template.copyWith(name: finalName, elements: provider.elements.toList());
      final pdfJson = {
        'name': finalName,
        'pageSize': snapshot.pageSize.toJson(),
        'elements': snapshot.elements.map((e) => e.toJson()).toList(),
      };
      Navigator.of(ctx).pop();
      try {
        final token = await widget.tokenProvider?.call();
        final uri =
            Uri.parse(widget.apiBaseUrl).resolve('/api/pdf-templates');
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'name': finalName, 'pdfJson': pdfJson}),
        );
        if (!context.mounted) return;
        if (response.statusCode == 201) {
          final respBody =
              jsonDecode(response.body) as Map<String, dynamic>;
          final newId = (respBody['template'] as Map<String, dynamic>?)
              ?['id'] as String?;
          if (newId != null) setState(() => _currentTemplateId = newId);
          widget.onTemplateSaved?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Template saved'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          String msg = 'Save failed (HTTP ${response.statusCode})';
          try {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            msg = body['message'] as String? ?? msg;
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save template: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as Template'),
        content: TextFormField(
          initialValue: initialName,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template name',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => enteredName = v,
          onFieldSubmitted: (_) => submit(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => submit(ctx),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _doUpdateTemplate(
      BuildContext context, TemplateEditorProvider provider, dynamic template) async {
    final templateId = _currentTemplateId;
    if (templateId == null) return;
    final snapshot =
        template.copyWith(name: template.name, elements: provider.elements.toList());
    final pdfJson = {
      'name': snapshot.name,
      'pageSize': snapshot.pageSize.toJson(),
      'elements': snapshot.elements.map((e) => e.toJson()).toList(),
    };
    try {
      final token = await widget.tokenProvider?.call();
      final uri = Uri.parse(widget.apiBaseUrl)
          .resolve('/api/pdf-templates/$templateId');
      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': snapshot.name, 'pdfJson': pdfJson}),
      );
      if (!context.mounted) return;
      if (response.statusCode == 200) {
        widget.onTemplateSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        String msg = 'Update failed (HTTP ${response.statusCode})';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          msg = body['message'] as String? ?? msg;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update template: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _runExport(
    BuildContext context,
    TemplateEditorProvider provider, {
    required _ExportMode mode,
  }) async {
    final template = provider.template;
    if (template == null) return;
    final exportService = context.read<PdfExportService>();
    final snapshot = template.copyWith(elements: provider.elements.toList());
    final name = snapshot.name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final fileName = (name.isEmpty ? 'document' : name) + '.pdf';

    try {
      switch (mode) {
        case _ExportMode.print:
          await exportService.printPdf(
            templateId: snapshot.id,
            elements: snapshot.elements,
            pageSize: snapshot.pageSize,
            fileName: snapshot.name.isEmpty ? 'Document' : snapshot.name,
          );
        case _ExportMode.download:
          await exportService.downloadPdf(
            templateId: snapshot.id,
            elements: snapshot.elements,
            pageSize: snapshot.pageSize,
            fileName: fileName,
          );
        case _ExportMode.share:
          await exportService.sharePdf(
            templateId: snapshot.id,
            elements: snapshot.elements,
            pageSize: snapshot.pageSize,
            fileName: fileName,
          );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

enum _ExportMode { download, print, share }

enum _ToolbarMenuAction { share, download, print, saveTemplate }

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _EmbeddedToolbar extends StatelessWidget {
  final TemplateEditorProvider provider;
  final VoidCallback? onClose;
  final VoidCallback onPreview;
  final VoidCallback onDownload;
  final VoidCallback onPrint;
  final VoidCallback onShare;
  final VoidCallback? onSaveAsTemplate;
  final bool isTemplateUpdateMode;
  final VoidCallback? onSave;

  const _EmbeddedToolbar({
    required this.provider,
    required this.onClose,
    required this.onPreview,
    required this.onDownload,
    required this.onPrint,
    required this.onShare,
    this.onSaveAsTemplate,
    this.isTemplateUpdateMode = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final perm = ProjectPermissionScope.of(context);
    final canExport = perm.canExport;
    final canEdit = perm.canEditDocument;
    if (MediaQuery.sizeOf(context).width < 560) {
      return _buildMobileToolbar(context, canExport: canExport, canEdit: canEdit);
    }
    final pageW = provider.template?.pageSize.width.round() ?? 595;
    final pageH = provider.template?.pageSize.height.round() ?? 842;

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      child: Row(
        children: [
          if (onClose != null) ...[
            _IconBtn(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Close editor',
              onTap: onClose!,
            ),
            const SizedBox(width: AppSpacing.s2),
            Container(
              width: 1,
              height: 24,
              color: AppColors.border,
            ),
            const SizedBox(width: AppSpacing.s3),
          ],

          // Document title + meta
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditableTitle(
                  name: provider.template?.name ?? '',
                  placeholder: 'Untitled document',
                  enabled: canEdit,
                  onRename: provider.renameTemplate,
                ),
                const SizedBox(height: 2),
                Text(
                  'PDF · $pageW × $pageH pt',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.bodyMuted,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.s4),

          // Undo / Redo group
          _ToolGroup(children: [
            _UndoRedoButtons(provider: provider),
          ]),

          const SizedBox(width: AppSpacing.s2),

          // Insert group
          _ToolGroup(children: [
            _IconBtn(
              icon: Icons.image_outlined,
              tooltip: 'Insert Image',
              onTap: () => provider.addElement(ImageElement.defaults()),
            ),
            _IconBtn(
              icon: Icons.table_chart_outlined,
              tooltip: 'Insert Table',
              onTap: () => provider.addElement(TableElement.defaults()),
            ),
            _IconBtn(
              icon: Icons.crop_square_outlined,
              tooltip: 'Insert Shape',
              onTap: () => provider.addElement(ShapeElement.defaults()),
            ),
            _IconBtn(
              icon: Icons.web_asset_outlined,
              tooltip: 'Insert Container',
              onTap: () => provider.addElement(ContainerElement.defaults()),
            ),
          ]),

          const Spacer(),

          // Export group — share / download / print
          if (canExport)
            _ToolGroup(children: [
              _IconBtn(
                icon: Icons.share_outlined,
                tooltip: 'Share PDF',
                onTap: onShare,
              ),
              _IconBtn(
                icon: Icons.file_download_outlined,
                tooltip: 'Download PDF',
                onTap: onDownload,
              ),
              _IconBtn(
                icon: Icons.print_outlined,
                tooltip: 'Print PDF',
                onTap: onPrint,
              ),
            ]),

// Templates button — save / update template (independent of project)
          if (canEdit && onSaveAsTemplate != null) ...[            

            const SizedBox(width: AppSpacing.s2),
            _TemplatesSaveButton(
                onSave: onSaveAsTemplate,
                isUpdate: isTemplateUpdateMode),
          ],

          const SizedBox(width: AppSpacing.s2),

          // Save — persists PDF document to the active project.
          // Only shown when a project is open (onSave != null).
          if (canEdit && onSave != null) ...[

            SizedBox(
              height: 36,
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
          ],

          // Preview — primary action
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              onPressed: onPreview,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Preview'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileToolbar(BuildContext context,
      {required bool canExport, required bool canEdit}) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      child: Row(
        children: [
          if (onClose != null)
            _IconBtn(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Close editor',
              onTap: onClose!,
            ),
          const SizedBox(width: 4),
          Expanded(
            child: _EditableTitle(
              name: provider.template?.name ?? '',
              placeholder: 'Untitled document',
              enabled: ProjectPermissionScope.of(context).canEditDocument,
              onRename: provider.renameTemplate,
            ),
          ),
          Consumer<TemplateEditorProvider>(
            builder: (_, prov, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconBtn(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo',
                  onTap: prov.canUndo ? prov.undo : null,
                ),
                _IconBtn(
                  icon: Icons.redo_rounded,
                  tooltip: 'Redo',
                  onTap: prov.canRedo ? prov.redo : null,
                ),
              ],
            ),
          ),
          if (canEdit && onSave != null)
            _IconBtn(
              icon: Icons.save_outlined,
              tooltip: 'Save',
              onTap: onSave,
            ),
          _IconBtn(
            icon: Icons.visibility_outlined,
            tooltip: 'Preview',
            onTap: onPreview,
          ),
          PopupMenuButton<_ToolbarMenuAction>(
            icon: const Icon(
              Icons.more_vert,
              size: 20,
              color: AppColors.bodyMuted,
            ),
            tooltip: 'More options',
            onSelected: (action) {
              switch (action) {
                case _ToolbarMenuAction.share:
                  onShare();
                case _ToolbarMenuAction.download:
                  onDownload();
                case _ToolbarMenuAction.print:
                  onPrint();
                case _ToolbarMenuAction.saveTemplate:
                  onSaveAsTemplate?.call();
              }
            },
            itemBuilder: (_) => [
              if (canExport) ...[
                const PopupMenuItem(
                  value: _ToolbarMenuAction.share,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.share_outlined),
                    title: Text('Share PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _ToolbarMenuAction.download,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('Download PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _ToolbarMenuAction.print,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.print_outlined),
                    title: Text('Print PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (canEdit && onSaveAsTemplate != null)
                PopupMenuItem(
                  value: _ToolbarMenuAction.saveTemplate,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.bookmark_add_outlined),
                    title: Text(isTemplateUpdateMode
                        ? 'Update Template'
                        : 'Save as Template'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Groups related icon buttons inside a subtle pill background so they read
/// as one cluster (Figma-style toolbar grouping).
class _ToolGroup extends StatelessWidget {
  final List<Widget> children;
  const _ToolGroup({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
}

// ── Templates dropdown button ─────────────────────────────────────────────────

class _TemplatesSaveButton extends StatelessWidget {
  final VoidCallback? onSave;
  final bool isUpdate;

  const _TemplatesSaveButton({this.onSave, this.isUpdate = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: onSave,
        icon: Icon(
          isUpdate ? Icons.bookmark_added_outlined : Icons.bookmark_add_outlined,
          size: 15,
        ),
        label: Text(
          isUpdate ? 'Update Template' : 'Save as Template',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _UndoRedoButtons extends StatelessWidget {
  final TemplateEditorProvider provider;

  const _UndoRedoButtons({required this.provider});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconBtn(
            icon: Icons.undo_rounded,
            tooltip: 'Undo (⌘Z)',
            onTap: provider.canUndo ? provider.undo : null,
            badge: provider.undoCount > 0 ? '${provider.undoCount}' : null,
          ),
          _IconBtn(
            icon: Icons.redo_rounded,
            tooltip: 'Redo (⌘⇧Z)',
            onTap: provider.canRedo ? provider.redo : null,
            badge: provider.redoCount > 0 ? '${provider.redoCount}' : null,
          ),
        ],
      );
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final String? badge;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge,
  });

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = enabled ? AppColors.body : AppColors.bodySubtle;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = enabled),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _hover
                  ? AppColors.primaryLight.withValues(alpha: 0.6)
                  : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(widget.icon, size: 17, color: color),
                if (widget.badge != null)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 12, minHeight: 12),
                      child: Text(
                        widget.badge!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Editor body ───────────────────────────────────────────────────────────────

class _EditorBody extends StatelessWidget {
  final TemplateEditorProvider provider;
  final List<String> frameUrls;

  const _EditorBody({required this.provider, this.frameUrls = const []});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 900;
    return Consumer<TemplateEditorProvider>(
      builder: (context, prov, _) {
        return Row(
          children: [
            if (isDesktop) const LeftPanelLayers(),
            Expanded(
              child: MouseRegion(
                onEnter: (_) {
                  if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
                },
                onExit: (_) {
                  if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
                },
                child: const EditorCanvasWidget(),
              ),
            ),
            if (prov.isImagePickerOpen)
              _ImagePickerSidebar(
                provider: prov,
                frameUrls: frameUrls,
              ),
          ],
        );
      },
    );
  }
}

// ── Image picker sidebar ──────────────────────────────────────────────────────

class _ImagePickerSidebar extends StatelessWidget {
  final TemplateEditorProvider provider;
  final List<String> frameUrls;

  const _ImagePickerSidebar({required this.provider, required this.frameUrls});

  @override
  Widget build(BuildContext context) {
    final ie = provider.primarySelected as ImageElement?;
    if (ie == null) return const SizedBox.shrink();

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text(
                  'Images',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.body,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: provider.closeImagePicker,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: AppColors.bodyMuted),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          if (frameUrls.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Text(
                'From recordings',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.bodyMuted,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemCount: frameUrls.length,
                itemBuilder: (context, i) {
                  final url = frameUrls[i];
                  return _FrameThumbnail(
                    url: url,
                    isSelected: ie.src == url,
                    onTap: () => provider.updateElement(ie.copyWith(src: url)),
                  );
                },
              ),
            ),
          ] else
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No recording images available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.bodyMuted),
                  ),
                ),
              ),
            ),
          const Divider(height: 1, thickness: 0.5),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SidebarUploadBtn(provider: provider, element: ie),
          ),
        ],
      ),
    );
  }
}

class _SidebarUploadBtn extends StatelessWidget {
  final TemplateEditorProvider provider;
  final ImageElement element;

  const _SidebarUploadBtn({required this.provider, required this.element});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _pickImage(),
        icon: const Icon(Icons.upload_outlined, size: 16),
        label: Text(element.src.isEmpty ? 'Upload Image' : 'Replace Image'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';
    final company =
        provider.companyId.isEmpty ? 'guest' : provider.companyId;
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'pdf-editor-images/$company/${DateTime.now().millisecondsSinceEpoch}-$safeName';
    try {
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();
      provider.updateElement(element.copyWith(src: url));
    } catch (_) {
      provider.updateElement(
          element.copyWith(src: 'data:$mime;base64,${base64Encode(bytes)}'));
    }
  }
}

class _FrameThumbnail extends StatelessWidget {
  final String url;
  final bool isSelected;
  final VoidCallback onTap;

  const _FrameThumbnail({
    required this.url,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: const Color(0xFFF1F5F9),
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.bodyMuted,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

// ── No-op repository ──────────────────────────────────────────────────────────
// The module never persists to a backend — silently discards all save calls.

class _NoOpRepository implements TemplateRepository {
  @override
  Future<TemplateModel?> fetchTemplate(String c, String id) async => null;

  @override
  Future<void> updateTemplate(String c, TemplateModel t) async {}

  @override
  Future<TemplateModel> createTemplate(String c, TemplateModel t) async => t;

  @override
  Future<void> deleteTemplate(String c, String id) async {}

  @override
  Future<void> renameTemplate(String c, String id, String name) async {}

  @override
  Future<TemplateModel> duplicateTemplate(String c, String id, String name) async =>
      throw UnimplementedError();

  @override
  Future<TemplatePageResult> fetchTemplates(String c,
          {TemplateType? type, Object? cursor}) async =>
      const TemplatePageResult(items: []);

  @override
  Future<List<TemplateModel>> fetchPresetTemplates() async => [];

  @override
  Stream<List<TemplateModel>> watchTemplates(String c,
          {TemplateType? type}) =>
      const Stream.empty();
}

// ── Template picker dialog ────────────────────────────────────────────────────

class _TemplatePickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> templates;

  const _TemplatePickerDialog({
    required this.templates,
  });

  @override
  State<_TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<_TemplatePickerDialog> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.templates);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PDF Templates'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 380,
        child: _items.isEmpty
            ? const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Text(
                  'No saved templates yet.',
                  style: TextStyle(color: AppColors.bodyMuted),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (ctx, i) {
                  final t = _items[i];
                  final name = t['name'] as String? ?? 'Untitled';
                  return ListTile(
                    leading: const Icon(
                        Icons.article_outlined,
                        color: AppColors.primary),
                    title: Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                      'Tap to load into editor',
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: null,
                    onTap: () => Navigator.of(ctx).pop(t),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ── Inline editable title ─────────────────────────────────────────────────────

class _EditableTitle extends StatefulWidget {
  final String name;
  final String placeholder;
  final bool enabled;
  final ValueChanged<String> onRename;

  const _EditableTitle({
    required this.name,
    required this.placeholder,
    required this.enabled,
    required this.onRename,
  });

  @override
  State<_EditableTitle> createState() => _EditableTitleState();
}

class _EditableTitleState extends State<_EditableTitle> {
  static const TextStyle _style = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 14,
    color: AppColors.body,
    height: 1.2,
  );

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
    _focusNode = FocusNode(onKeyEvent: _handleKey);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _EditableTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.name != _controller.text) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _editing) _commit();
  }

  void _startEditing() {
    if (!widget.enabled) return;
    setState(() => _editing = true);
    _controller.text = widget.name;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _commit() {
    final next = _controller.text.trim();
    setState(() => _editing = false);
    if (next.isNotEmpty && next != widget.name) {
      widget.onRename(next);
    } else {
      _controller.text = widget.name;
    }
  }

  void _cancel() {
    if (!mounted) return;
    setState(() => _editing = false);
    _controller.text = widget.name;
    _focusNode.unfocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        height: 24,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: _style,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            _focusNode.unfocus();
          },
          decoration: const InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          onEditingComplete: () => _focusNode.unfocus(),
          onTapOutside: (_) => _focusNode.unfocus(),
        ),
      );
    }

    final display = widget.name.isNotEmpty ? widget.name : widget.placeholder;
    final isPlaceholder = widget.name.isEmpty;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.text
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startEditing,
        child: Tooltip(
          message: widget.enabled ? 'Rename document' : '',
          child: Text(
            display,
            style: _style.copyWith(
              color: isPlaceholder ? AppColors.bodyMuted : AppColors.body,
              fontStyle:
                  isPlaceholder ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
