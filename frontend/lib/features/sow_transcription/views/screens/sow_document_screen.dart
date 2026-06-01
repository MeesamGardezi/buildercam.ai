// Purpose: View, edit, and export a Scope of Work document with AI-powered PDF generation.
import 'package:buildercam/core/core.dart';
import 'package:buildercam/core/router/app_router.dart';
import 'package:buildercam/features/auth/auth_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/sow_template_model.dart';
import '../../services/sow_editor_converter.dart';
import '../../services/sow_firestore_service.dart';
import '../../services/sow_pdf_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen widget
// ─────────────────────────────────────────────────────────────────────────────

class SowDocumentScreen extends StatefulWidget {
  const SowDocumentScreen({
    super.key,
    required this.projectName,
    required this.initialContent,
    this.clientName = '',
    this.siteLocation = '',
    this.scopeSummary = '',
    this.projectId,
    this.documentId,
    this.transcriptIds = const [],
    this.frameUrls = const [],
    this.sowTemplates = const [],
    this.pdfTemplates = const [],
    this.backendService,
    this.onBack,
    this.onOpenPdfEditor,
    this.onDocumentSaved,
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
  final List<SowTemplateModel> sowTemplates;
  final List<Map<String, dynamic>> pdfTemplates;
  final SowBackendService? backendService;

  /// Called when the back button is pressed. Falls back to [context.pop] when null.
  final VoidCallback? onBack;

  /// Called to open the PDF editor inline. Falls back to a GoRouter push when null.
  final void Function(PdfEditorArgs args)? onOpenPdfEditor;

  /// Called after the first save of a new document, with the assigned ID.
  final void Function(String savedDocId)? onDocumentSaved;

  static Future<void> show(
    BuildContext context, {
    required String projectName,
    required String content,
    String clientName = '',
    String siteLocation = '',
    String scopeSummary = '',
    String? projectId,
    String? documentId,
    List<String> transcriptIds = const [],
    List<String> frameUrls = const [],
    SowBackendService? backendService,
  }) async {
    final args = SowDocumentArgs(
      projectName: projectName,
      initialContent: content,
      clientName: clientName,
      siteLocation: siteLocation,
      scopeSummary: scopeSummary,
      projectId: projectId,
      documentId: documentId,
      transcriptIds: transcriptIds,
      frameUrls: frameUrls,
      backendService: backendService,
    );
    if (projectId != null) {
      // Embedded in shell with sidebar — use go() so the URL changes.
      context.go(
        '/project/$projectId/sow/${documentId ?? 'new'}',
        extra: args,
      );
    } else {
      // Template / standalone — fullscreen push.
      await context.push(AppRoute.sowTemplate.path, extra: args);
    }
  }

  @override
  State<SowDocumentScreen> createState() => _SowDocumentScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _SowDocumentScreenState extends State<SowDocumentScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  String? _savedDocId;
  bool _isSaving = false;
  bool _isEditMode = false;
  bool _isGeneratingAiPdf = false;
  bool _isPdfDialogOpen = false;

  List<_SowSection> _sections = [];

  static const _pdfService = SowPdfService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: 'SOW — ${widget.projectName}',
    );
    _contentController = TextEditingController(text: widget.initialContent);
    _savedDocId = widget.documentId;
    _parseSections();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ── Section parsing ────────────────────────────────────────────────────────

  void _parseSections() {
    _sections = _SowSection.parseFromText(_contentController.text);
  }

  void _syncSectionsToContent() {
    final buffer = StringBuffer();
    for (final section in _sections) {
      if (section.heading.isNotEmpty) {
        buffer.writeln(section.heading);
      }
      buffer.writeln(section.body);
      buffer.writeln();
    }
    _contentController.text = buffer.toString().trim();
  }

  // ── PDF generation ─────────────────────────────────────────────────────────

  Future<void> _openPdfEditor() async {
    if (_isGeneratingAiPdf || _isPdfDialogOpen) return;

    // Always show the instructions dialog — instructions are optional.
    setState(() => _isPdfDialogOpen = true);
    final result = await showDialog<_AiPdfDialogResult>(
      context: context,
      builder: (_) => _AiPdfDialog(
        templates: widget.sowTemplates,
        pdfTemplates: widget.pdfTemplates,
      ),
    );
    if (!mounted) return;
    setState(() => _isPdfDialogOpen = false);
    if (result == null) return;

    // Build instructions, optionally prepending the selected template's
    // section structure so the AI follows it when formatting the PDF.
    final String effectiveInstructions;
    final selectedTemplate = result.selectedTemplate;
    final selectedPdfTemplate = result.selectedPdfTemplate;
    if (selectedTemplate != null) {
      final buf = StringBuffer();
      buf.writeln(
        'Follow this template structure for the PDF sections. '
        'Use exactly these section headings and organise all SOW '
        'content under them:',
      );
      buf.writeln();
      buf.writeln('=== TEMPLATE: ${selectedTemplate.name} ===');
      buf.writeln(selectedTemplate.content);
      buf.writeln('===');
      if (result.instructions.isNotEmpty) {
        buf.writeln();
        buf.writeln('Additional instructions: ${result.instructions}');
      }
      effectiveInstructions = buf.toString();
    } else if (selectedPdfTemplate != null) {
      // Extract section names from the PDF layout template's text elements.
      final pdfJson = selectedPdfTemplate['pdfJson'];
      final sectionTexts = <String>[];
      if (pdfJson is Map<String, dynamic> && pdfJson['elements'] is List) {
        for (final el in (pdfJson['elements'] as List)) {
          if (el is Map<String, dynamic> && el['type'] == 'text') {
            final content = el['content']?.toString().trim() ?? '';
            if (content.isNotEmpty) sectionTexts.add(content);
          }
        }
      }
      final buf = StringBuffer();
      buf.writeln(
        'Follow this PDF layout template structure when organising the document. '
        'Use the following section headings and labels from the template:',
      );
      buf.writeln();
      buf.writeln('=== PDF TEMPLATE: ${selectedPdfTemplate['name']} ===');
      if (sectionTexts.isNotEmpty) {
        for (final t in sectionTexts) {
          buf.writeln('- $t');
        }
      } else {
        buf.writeln('(structure the content to match this layout template)');
      }
      buf.writeln('===');
      if (result.instructions.isNotEmpty) {
        buf.writeln();
        buf.writeln('Additional instructions: ${result.instructions}');
      }
      effectiveInstructions = buf.toString();
    } else {
      effectiveInstructions = result.instructions;
    }

    setState(() => _isGeneratingAiPdf = true);
    try {
      // structureSow throws if Gemini isn't configured or the call fails.
      final sections = await _pdfService.structureSow(
        _contentController.text,
        instructions: effectiveInstructions,
        tokenProvider: widget.backendService?.tokenProvider,
      );
      if (!mounted) return;
      _openInEditor(sections);
    } catch (e) {
      if (!mounted) return;
      _showSnack('AI PDF failed: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingAiPdf = false);
    }
  }

  void _openInEditor(List<SowPdfSection> sections) {
    final docData = SowEditorConverter.convert(
      projectName: widget.projectName,
      clientName: widget.clientName,
      siteLocation: widget.siteLocation,
      sections: sections,
    );
    final args = PdfEditorArgs(
      initialData: docData,
      apiBaseUrl: ApiConfig.sowProxyBaseUrl,
      projectId: widget.projectId,
      frameUrls: widget.frameUrls,
      tokenProvider: widget.backendService?.tokenProvider,
    );
    if (widget.onOpenPdfEditor != null) {
      widget.onOpenPdfEditor!(args);
    } else {
      // Fallback: standalone / template mode — navigate via router.
      context.pushNamed(
        AppRoute.pdfEditor.name,
        pathParameters: {
          'projectId': widget.projectId ?? 'demo',
          'sowId': _savedDocId ?? widget.documentId ?? 'new',
        },
        extra: args,
      );
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final service = widget.backendService;
    final projectId = widget.projectId;
    if (service == null || projectId == null) {
      _showSnack('Cannot save — missing project context');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final doc = await service.saveSowDocument(
        projectId: projectId,
        id: _savedDocId,
        title: _titleController.text.trim().isEmpty
            ? 'SOW — ${widget.projectName}'
            : _titleController.text.trim(),
        content: _contentController.text,
        transcriptIds: widget.transcriptIds,
        frameUrls: widget.frameUrls,
      );
      setState(() => _savedDocId = doc.id);
      // Fire on every save so the parent can refresh its sidebar lists.
      widget.onDocumentSaved?.call(doc.id);
      _showSnack('Document saved');
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _contentController.text));
    _showSnack('Copied to clipboard');
  }

  Future<void> _shareText() async {
    await Share.share(
      '${widget.projectName}\n\n${_contentController.text}',
      subject: 'Scope of Work — ${widget.projectName}',
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perm = ProjectPermissionScope.of(context);
    final canEdit = perm.canEditDocument;
    final canSave =
        canEdit && widget.backendService != null && widget.projectId != null;
    final body = Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: _buildAppBar(theme, canSave, canEdit),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DocumentTitleBar(
              titleController: _titleController,
              projectName: widget.projectName,
              clientName: widget.clientName,
              siteLocation: widget.siteLocation,
              savedDocId: _savedDocId,
              isEditMode: _isEditMode,
              theme: theme,
            ),
            Expanded(
              child: _isEditMode
                  ? _SectionEditor(
                      contentController: _contentController,
                      sections: _sections,
                      onSectionChanged: () {
                        _syncSectionsToContent();
                        setState(() => _parseSections());
                      },
                      onRawTextChanged: () => setState(() => _parseSections()),
                      theme: theme,
                    )
                  : _DocumentViewer(
                      sections: _sections,
                      content: _contentController.text,
                      theme: theme,
                    ),
            ),
            _ActionBar(
              isSaving: _isSaving,
              isGeneratingAiPdf: _isGeneratingAiPdf,
              canSave: canSave,
              canEdit: canEdit,
              onSave: _save,
              onOpenEditor: _openPdfEditor,
              onCopy: _copyToClipboard,
              onShare: _shareText,
            ),
          ],
        ),
      ),
    );
    final projectId = widget.projectId;
    if (projectId == null) return body;
    return ProjectPermissionScope.load(projectId: projectId, child: body);
  }

  PreferredSizeWidget _buildAppBar(
      ThemeData theme, bool canSave, bool canEdit) {
    return AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: AppColors.border,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: widget.onBack ?? () => context.pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scope of Work',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            widget.projectName,
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        if (canSave)
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    _savedDocId != null
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_upload_rounded,
                    color: _savedDocId != null
                        ? AppColors.success
                        : AppColors.bodyMuted,
                  ),
                  tooltip:
                      _savedDocId != null ? 'Saved to cloud' : 'Save to cloud',
                  onPressed: _save,
                ),
        // Edit / View toggle (hidden for members without edit permission).
        if (canEdit)
          IconButton(
            icon: Icon(
              _isEditMode ? Icons.visibility_rounded : Icons.edit_rounded,
              color: _isEditMode ? AppColors.primary : AppColors.bodyMuted,
            ),
            tooltip: _isEditMode ? 'View document' : 'Edit document',
            onPressed: () {
              if (_isEditMode) {
                setState(() {
                  _parseSections();
                  _isEditMode = false;
                });
              } else {
                setState(() => _isEditMode = true);
              }
            },
          ),
        // Overflow menu
        PopupMenuButton<_MenuAction>(
          icon:
              const Icon(Icons.more_vert_rounded, color: AppColors.bodyMuted),
          onSelected: (action) {
            switch (action) {
              case _MenuAction.copy:
                _copyToClipboard();
              case _MenuAction.share:
                _shareText();
              case _MenuAction.openEditor:
                _openPdfEditor();
            }
          },
          itemBuilder: (_) => [
            if (canEdit) ...[
              const PopupMenuItem(
                value: _MenuAction.openEditor,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.auto_awesome_rounded,
                      color: AppColors.primary),
                  title: Text('Open in PDF editor'),
                  subtitle: Text('Structure with AI · freeform layout'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem(
              value: _MenuAction.copy,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.copy_rounded),
                title: Text('Copy to clipboard'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: _MenuAction.share,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.ios_share_rounded),
                title: Text('Share'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document title bar
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentTitleBar extends StatelessWidget {
  const _DocumentTitleBar({
    required this.titleController,
    required this.projectName,
    required this.clientName,
    required this.siteLocation,
    required this.savedDocId,
    required this.isEditMode,
    required this.theme,
  });

  final TextEditingController titleController;
  final String projectName;
  final String clientName;
  final String siteLocation;
  final String? savedDocId;
  final bool isEditMode;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4, AppSpacing.s3, AppSpacing.s4, AppSpacing.s3),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEditMode) ...[
            TextField(
              controller: titleController,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: AppInputs.standard(
                labelText: 'Document title',
                hintText: 'SOW — $projectName',
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
          ] else ...[
            Text(
              titleController.text.isEmpty
                  ? 'SOW — $projectName'
                  : titleController.text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (clientName.isNotEmpty)
                _MetaChip(
                    icon: Icons.person_outline_rounded, label: clientName),
              if (siteLocation.isNotEmpty)
                _MetaChip(
                    icon: Icons.location_on_outlined, label: siteLocation),
              if (savedDocId != null)
                const _MetaChip(
                  icon: Icons.cloud_done_rounded,
                  label: 'Saved',
                  color: AppColors.success,
                  bgColor: AppColors.successLight,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.color = AppColors.bodyMuted,
    this.bgColor = AppColors.surfaceRaised,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document Viewer — read-only formatted view
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentViewer extends StatelessWidget {
  const _DocumentViewer({
    required this.sections,
    required this.content,
    required this.theme,
  });

  final List<_SowSection> sections;
  final String content;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty && content.trim().isEmpty) {
      return _EmptyDocumentState(theme: theme);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4, AppSpacing.s4, AppSpacing.s4, AppSpacing.s6),
      itemCount: sections.isEmpty ? 1 : sections.length,
      itemBuilder: (context, index) {
        if (sections.isEmpty) {
          return _RawContentCard(content: content, theme: theme);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s3),
          child: _SectionViewCard(section: sections[index], theme: theme),
        );
      },
    );
  }
}

class _SectionViewCard extends StatelessWidget {
  const _SectionViewCard({required this.section, required this.theme});

  final _SowSection section;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.heading.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4, AppSpacing.s3, AppSpacing.s4, AppSpacing.s3),
              decoration: const BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusLg),
                ),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.heading,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s4,
              section.heading.isEmpty ? AppSpacing.s4 : AppSpacing.s4,
              AppSpacing.s4,
              AppSpacing.s4,
            ),
            child: _RichBodyText(text: section.body, theme: theme),
          ),
        ],
      ),
    );
  }
}

class _RichBodyText extends StatelessWidget {
  const _RichBodyText({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    final bulletRe = RegExp(r'^\s*[-•–]\s+(.+)$');
    final numberedRe = RegExp(r'^\s*(\d+)\.\s+(.+)$');

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 6));
        continue;
      }
      final bulletMatch = bulletRe.firstMatch(t);
      final numberedMatch = numberedRe.firstMatch(t);

      if (bulletMatch != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 10),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    bulletMatch.group(1) ?? t,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (numberedMatch != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${numberedMatch.group(1)}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    numberedMatch.group(2) ?? t,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(t, style: theme.textTheme.bodyMedium),
          ),
        );
      }
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class _RawContentCard extends StatelessWidget {
  const _RawContentCard({required this.content, required this.theme});

  final String content;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Text(content, style: theme.textTheme.bodyMedium),
    );
  }
}

class _EmptyDocumentState extends StatelessWidget {
  const _EmptyDocumentState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined,
                size: 48, color: AppColors.bodySubtle),
            const SizedBox(height: AppSpacing.s3),
            Text('No content yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s2),
            Text(
              'Switch to edit mode to add content.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Editor — per-section or raw text editing
// ─────────────────────────────────────────────────────────────────────────────

class _SectionEditor extends StatefulWidget {
  const _SectionEditor({
    required this.contentController,
    required this.sections,
    required this.onSectionChanged,
    required this.onRawTextChanged,
    required this.theme,
  });

  final TextEditingController contentController;
  final List<_SowSection> sections;
  final VoidCallback onSectionChanged;
  final VoidCallback onRawTextChanged;
  final ThemeData theme;

  @override
  State<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<_SectionEditor> {
  bool _rawMode = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode toggle bar
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4, AppSpacing.s2, AppSpacing.s4, AppSpacing.s2),
          decoration: const BoxDecoration(
            color: AppColors.surfaceRaised,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  size: 15, color: AppColors.bodyMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _rawMode
                      ? 'Editing full document text'
                      : 'Tap a section heading or body to edit',
                  style: widget.theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.bodyMuted),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _rawMode = !_rawMode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusFull),
                    border: Border.all(color: AppColors.borderStrong),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _rawMode
                            ? Icons.view_list_rounded
                            : Icons.code_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _rawMode ? 'Sections' : 'Raw text',
                        style: widget.theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rawMode
              ? _RawTextEditor(
                  controller: widget.contentController,
                  onChanged: widget.onRawTextChanged,
                  theme: widget.theme,
                )
              : _SectionListEditor(
                  sections: widget.sections,
                  onSectionChanged: widget.onSectionChanged,
                  theme: widget.theme,
                ),
        ),
      ],
    );
  }
}

class _RawTextEditor extends StatelessWidget {
  const _RawTextEditor({
    required this.controller,
    required this.onChanged,
    required this.theme,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(AppSpacing.s4),
            hintText: 'Document content…',
            hintStyle: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.bodySubtle),
          ),
        ),
      ),
    );
  }
}

class _SectionListEditor extends StatelessWidget {
  const _SectionListEditor({
    required this.sections,
    required this.onSectionChanged,
    required this.theme,
  });

  final List<_SowSection> sections;
  final VoidCallback onSectionChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.text_snippet_outlined,
                  size: 44, color: AppColors.bodySubtle),
              const SizedBox(height: AppSpacing.s3),
              Text('No sections detected', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'Switch to Raw Text mode to edit the full document.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.bodyMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4, AppSpacing.s4, AppSpacing.s4, AppSpacing.s6),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s3),
          child: _SectionEditCard(
            section: sections[index],
            onChanged: onSectionChanged,
            theme: theme,
          ),
        );
      },
    );
  }
}

class _SectionEditCard extends StatefulWidget {
  const _SectionEditCard({
    required this.section,
    required this.onChanged,
    required this.theme,
  });

  final _SowSection section;
  final VoidCallback onChanged;
  final ThemeData theme;

  @override
  State<_SectionEditCard> createState() => _SectionEditCardState();
}

class _SectionEditCardState extends State<_SectionEditCard> {
  late final TextEditingController _headingCtrl;
  late final TextEditingController _bodyCtrl;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _headingCtrl = TextEditingController(text: widget.section.heading);
    _bodyCtrl = TextEditingController(text: widget.section.body);
    _headingCtrl.addListener(_sync);
    _bodyCtrl.addListener(_sync);
  }

  @override
  void dispose() {
    _headingCtrl.removeListener(_sync);
    _bodyCtrl.removeListener(_sync);
    _headingCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    widget.section.heading = _headingCtrl.text;
    widget.section.body = _bodyCtrl.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heading row — tappable to collapse/expand
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(AppSpacing.radiusLg),
              bottom: _isExpanded
                  ? Radius.zero
                  : const Radius.circular(AppSpacing.radiusLg),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4, AppSpacing.s3, AppSpacing.s3, AppSpacing.s3),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(AppSpacing.radiusLg),
                  bottom: _isExpanded
                      ? Radius.zero
                      : const Radius.circular(AppSpacing.radiusLg),
                ),
                border: _isExpanded
                    ? const Border(
                        bottom: BorderSide(color: AppColors.border))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _headingCtrl,
                      style: widget.theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Section heading…',
                      ),
                      onTap: () {
                        if (!_isExpanded) {
                          setState(() => _isExpanded = true);
                        }
                      },
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.bodyMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Body editor (collapsible)
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s3),
              child: TextField(
                controller: _bodyCtrl,
                maxLines: null,
                minLines: 3,
                style:
                    widget.theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.s3),
                  isDense: true,
                  hintText: 'Section content…',
                  hintStyle: widget.theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.bodySubtle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom action bar
// ─────────────────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isSaving,
    required this.isGeneratingAiPdf,
    required this.canSave,
    required this.canEdit,
    required this.onSave,
    required this.onOpenEditor,
    required this.onCopy,
    required this.onShare,
  });

  final bool isSaving;
  final bool isGeneratingAiPdf;
  final bool canSave;
  final bool canEdit;
  final VoidCallback onSave;
  final VoidCallback onOpenEditor;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 420;
        return Container(
          padding: EdgeInsets.fromLTRB(
            isCompact ? AppSpacing.s2 : AppSpacing.s4,
            AppSpacing.s2,
            isCompact ? AppSpacing.s2 : AppSpacing.s4,
            AppSpacing.s2,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 20),
                tooltip: 'Copy to clipboard',
                visualDensity: isCompact ? VisualDensity.compact : null,
                style: IconButton.styleFrom(
                    foregroundColor: AppColors.bodyMuted),
              ),
              IconButton(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                tooltip: 'Share',
                visualDensity: isCompact ? VisualDensity.compact : null,
                style: IconButton.styleFrom(
                    foregroundColor: AppColors.bodyMuted),
              ),
              const Spacer(),
              if (canEdit)
                FilledButton.icon(
                  onPressed: isGeneratingAiPdf ? null : onOpenEditor,
                  icon: isGeneratingAiPdf
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    isGeneratingAiPdf
                        ? 'Building…'
                        : (isCompact ? 'PDF Editor' : 'Open PDF editor'),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          isCompact ? AppSpacing.s2 : AppSpacing.s4,
                      vertical: AppSpacing.s2,
                    ),
                    minimumSize: const Size(0, 36),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                ),
              if (canSave) ...[
                SizedBox(width: isCompact ? 4 : AppSpacing.s2),
                FilledButton.icon(
                  onPressed: isSaving ? null : onSave,
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: Text(isSaving ? 'Saving…' : 'Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          isCompact ? AppSpacing.s2 : AppSpacing.s4,
                      vertical: AppSpacing.s2,
                    ),
                    minimumSize: const Size(0, 36),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section data model (mutable for inline editing)
// ─────────────────────────────────────────────────────────────────────────────

class _SowSection {
  _SowSection({required this.heading, required this.body});

  String heading;
  String body;

  static List<_SowSection> parseFromText(String text) {
    if (text.trim().isEmpty) return [];

    final lines = text.split('\n');
    final sections = <_SowSection>[];
    String currentHeading = '';
    final bodyLines = <String>[];

    // Detect numbered headings (e.g. "1. Scope of Work") or ALL-CAPS headings
    final headingRe = RegExp(
      r'^(\d+\.\s+[A-Z]|[A-Z][A-Z &/\-,]{3,}[A-Z:])\s*$',
    );

    void flush() {
      final body = bodyLines.join('\n').trim();
      if (currentHeading.isNotEmpty || body.isNotEmpty) {
        sections.add(_SowSection(heading: currentHeading, body: body));
        bodyLines.clear();
      }
    }

    for (final line in lines) {
      final t = line.trim();
      if (headingRe.hasMatch(t)) {
        flush();
        currentHeading = t;
      } else {
        bodyLines.add(line);
      }
    }
    flush();

    return sections;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result returned by the AI PDF dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AiPdfDialogResult {
  const _AiPdfDialogResult({
    required this.instructions,
    this.selectedTemplate,
    this.selectedPdfTemplate,
  });
  final String instructions;
  final SowTemplateModel? selectedTemplate;
  final Map<String, dynamic>? selectedPdfTemplate;
}

// ─────────────────────────────────────────────────────────────────────────────
// AI PDF instructions dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AiPdfDialog extends StatefulWidget {
  const _AiPdfDialog({
    this.templates = const [],
    this.pdfTemplates = const [],
  });

  final List<SowTemplateModel> templates;
  final List<Map<String, dynamic>> pdfTemplates;

  @override
  State<_AiPdfDialog> createState() => _AiPdfDialogState();
}

class _AiPdfDialogState extends State<_AiPdfDialog> {
  final _ctrl = TextEditingController();
  SowTemplateModel? _selectedTemplate;
  Map<String, dynamic>? _selectedPdfTemplate;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.blue100,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI PDF',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Gemini will structure & format the document',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.bodyMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.s4),
              // ── Template picker (always shown) ───────────────────────────
              Text(
                'Document template (optional)',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                'The AI will follow this template\'s section structure.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.bodyMuted),
              ),
              const SizedBox(height: AppSpacing.s2),
              if (widget.templates.isEmpty && widget.pdfTemplates.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_outline_rounded,
                          size: 15, color: AppColors.bodySubtle),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          'No templates saved yet. Create one in the Templates tab of the sidebar.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.bodyMuted),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // SOW text templates
                    ...widget.templates.map((t) {
                      final isSelected = _selectedTemplate?.id == t.id;
                      return FilterChip(
                        avatar: const Icon(Icons.description_outlined,
                            size: 14),
                        label: Text(t.name),
                        selected: isSelected,
                        onSelected: (_) => setState(() {
                          _selectedTemplate = isSelected ? null : t;
                          if (!isSelected) _selectedPdfTemplate = null;
                        }),
                        showCheckmark: true,
                        selectedColor: AppColors.primaryLight,
                        backgroundColor: AppColors.surfaceRaised,
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.borderStrong,
                        ),
                        labelStyle: theme.textTheme.labelMedium?.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.body,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      );
                    }),
                    // PDF layout templates
                    ...widget.pdfTemplates.map((t) {
                      final id = t['id']?.toString() ?? '';
                      final name = t['name']?.toString() ?? '';
                      final isSelected =
                          _selectedPdfTemplate?['id']?.toString() == id;
                      return FilterChip(
                        avatar: const Icon(Icons.picture_as_pdf_outlined,
                            size: 14),
                        label: Text(name),
                        selected: isSelected,
                        onSelected: (_) => setState(() {
                          _selectedPdfTemplate = isSelected ? null : t;
                          if (!isSelected) _selectedTemplate = null;
                        }),
                        showCheckmark: true,
                        selectedColor: AppColors.primaryLight,
                        backgroundColor: AppColors.surfaceRaised,
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.borderStrong,
                        ),
                        labelStyle: theme.textTheme.labelMedium?.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.body,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      );
                    }),
                  ],
                ),
              const SizedBox(height: AppSpacing.s4),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.s4),
              // ── Instructions field ──────────────────────────────────────
              Text(
                'Special instructions',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                controller: _ctrl,
                maxLines: 4,
                autofocus: widget.templates.isEmpty,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium,
                decoration: AppInputs.standard(
                  hintText:
                      'e.g. "Add a payment schedule section", "Emphasise safety requirements", "Group electrical items together"…',
                ).copyWith(
                  hintMaxLines: 4,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'Leave blank to structure the document as-is.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.bodyMuted),
              ),
              const SizedBox(height: AppSpacing.s5),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.bodyMuted,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size(0, 40),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(
                        _AiPdfDialogResult(
                          instructions: _ctrl.text.trim(),
                          selectedTemplate: _selectedTemplate,
                          selectedPdfTemplate: _selectedPdfTemplate,
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Generate PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(0, 40),
                      ),
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
// Pop-up menu action enum
// ─────────────────────────────────────────────────────────────────────────────

enum _MenuAction { copy, share, openEditor }


