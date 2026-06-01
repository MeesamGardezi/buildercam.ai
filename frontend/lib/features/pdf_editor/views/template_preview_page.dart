import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_spacing.dart';
import '../models/template_model.dart';
import '../services/pdf_export_service.dart';
import '../widgets/canvas/preview_canvas_widget.dart';

enum _PreviewMenuAction { share, print, download }

/// Full-screen read-only preview of a template.
///
/// Shows the template elements rendered on a scaled A4 canvas.
/// Toolbar provides Download PDF and Print actions that generate the
/// PDF on demand and handle it via [PdfExportService].
class TemplatePreviewPage extends StatefulWidget {
  final TemplateModel template;
  final PdfExportService exportService;
  final bool canExport;

  const TemplatePreviewPage({
    super.key,
    required this.template,
    required this.exportService,
    this.canExport = true,
  });

  @override
  State<TemplatePreviewPage> createState() => _TemplatePreviewPageState();
}

class _TemplatePreviewPageState extends State<TemplatePreviewPage> {
  bool _isGenerating = false;
  String? _errorMessage;

  Future<void> _share() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });
    try {
      await widget.exportService.sharePdf(
        templateId: widget.template.id,
        elements: widget.template.elements,
        pageSize: widget.template.pageSize,
        fileName: '${widget.template.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _download() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      await widget.exportService.downloadPdf(
        templateId: widget.template.id,
        elements: widget.template.elements,
        pageSize: widget.template.pageSize,
        fileName: '${widget.template.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _print() async {
    if (_isGenerating) return;
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      await widget.exportService.printPdf(
        templateId: widget.template.id,
        elements: widget.template.elements,
        pageSize: widget.template.pageSize,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 480;
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text(widget.template.name),
        centerTitle: false,
        actions: [
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3, vertical: 12),
              child: Text(
                'Error — try again',
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 12),
              ),
            ),
          _isGenerating
              ? const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : !widget.canExport
                  ? const SizedBox.shrink()
                  : isMobile
                  ? PopupMenuButton<_PreviewMenuAction>(
                      onSelected: (action) {
                        switch (action) {
                          case _PreviewMenuAction.share:
                            _share();
                          case _PreviewMenuAction.print:
                            _print();
                          case _PreviewMenuAction.download:
                            _download();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _PreviewMenuAction.share,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.share_outlined),
                            title: Text('Share'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: _PreviewMenuAction.print,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.print_outlined),
                            title: Text('Print'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: _PreviewMenuAction.download,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.download_outlined),
                            title: Text('Download PDF'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_outlined, size: 16),
                          label: const Text('Share'),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        TextButton.icon(
                          onPressed: _print,
                          icon: const Icon(Icons.print_outlined, size: 16),
                          label: const Text('Print'),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Padding(
                          padding: const EdgeInsets.only(
                              right: AppSpacing.s4),
                          child: FilledButton.icon(
                            onPressed: _download,
                            icon: const Icon(Icons.download_outlined,
                                size: 16),
                            label: const Text('Download PDF'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                              textStyle:
                                  const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
        ],
      ),
      body: PreviewCanvasWidget(template: widget.template),
    );
  }
}
