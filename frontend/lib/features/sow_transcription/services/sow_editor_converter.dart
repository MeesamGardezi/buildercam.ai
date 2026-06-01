// Purpose: Converts AI-structured SOW sections into a PdfDocumentData layout
// ready to be loaded into PdfEditorWidget for freeform editing.
import 'package:flutter/material.dart';
import 'package:buildercam/features/pdf_editor/models/pdf_document_data.dart';
import 'package:buildercam/features/pdf_editor/models/template_element_model.dart';
import 'package:buildercam/features/pdf_editor/models/template_model.dart';

import 'sow_pdf_service.dart';

/// Converts a list of [SowPdfSection]s + project metadata into a
/// [PdfDocumentData] that can be dropped directly into [PdfEditorWidget].
///
/// The layout targets A4 (595 × 842 pt) with 44 pt horizontal margins.
/// Elements stack vertically — the canvas is scrollable so sections that
/// exceed one page height remain editable.
class SowEditorConverter {
  const SowEditorConverter._();

  // ── Canvas constants ──────────────────────────────────────────────────────

  static const double _pageW = 595;
  static const double _marginX = 44;
  static const double _contentW = _pageW - _marginX * 2; // 507

  // Rough estimate: ~80 chars fit per line at font-size 10, content width 507
  static const double _charsPerLine = 80;
  static const double _bodyLineH = 15.0; // px per estimated line

  // ── Color palette (mirrors AppColors) ────────────────────────────────────

  static const _white = Color(0xFFFFFFFF);
  static const _primary = Color(0xFF0284C7);
  static const _body = Color(0xFF0F172A);
  static const _navyBg = Color(0xFF0C1A3A);
  static const _lightBlue = Color(0xFFBAE6FD);
  static const _border = Color(0xFFCBD5E1);

  // ── Public API ────────────────────────────────────────────────────────────

  static PdfDocumentData convert({
    required String projectName,
    required String clientName,
    required String siteLocation,
    required List<SowPdfSection> sections,
  }) {
    final elements = <TemplateElement>[];
    int z = 0;

    // ── Locked header region ──────────────────────────────────────────────

    // Dark navy background panel
    elements.add(
      TextElement.defaults(
        x: 0,
        y: 0,
        width: _pageW,
        height: 128,
        zIndex: z++,
        content: ' ',
      ).copyWith(
        fontSize: 1,
        color: _white,
        backgroundColor: _navyBg,
        locked: true,
      ),
    );

    // "SCOPE OF WORK" label
    elements.add(
      TextElement.defaults(
        x: _marginX,
        y: 20,
        width: _contentW,
        height: 16,
        zIndex: z++,
        content: 'SCOPE OF WORK',
      ).copyWith(
        fontSize: 7.5,
        fontWeight: FontWeight.w700,
        color: _lightBlue,
        letterSpacing: 2.5,
        locked: true,
      ),
    );

    // Project name
    elements.add(
      TextElement.defaults(
        x: _marginX,
        y: 42,
        width: _contentW,
        height: 38,
        zIndex: z++,
        content: projectName,
      ).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: _white,
        locked: true,
      ),
    );

    // Meta row (client | site | date)
    final metaParts = <String>[];
    if (clientName.isNotEmpty) metaParts.add('Client: $clientName');
    if (siteLocation.isNotEmpty) metaParts.add('Site: $siteLocation');
    metaParts.add('Date: ${_formatDate(DateTime.now())}');

    elements.add(
      TextElement.defaults(
        x: _marginX,
        y: 88,
        width: _contentW,
        height: 20,
        zIndex: z++,
        content: metaParts.join('   |   '),
      ).copyWith(
        fontSize: 9,
        color: _lightBlue,
        locked: true,
      ),
    );

    // Header bottom divider
    elements.add(
      DividerElement.defaults(
        x: 0,
        y: 128,
        width: _pageW,
        height: 2,
        zIndex: z++,
      ).copyWith(
        color: _border,
        locked: true,
      ),
    );

    double y = 150;

    // ── Sections ──────────────────────────────────────────────────────────

    for (final section in sections) {
      final bodyText = _buildBodyText(section.items);
      final bodyH = _estimateHeight(bodyText);

      // Heading
      if (section.heading.isNotEmpty) {
        // Blue left-accent bar
        elements.add(
          DividerElement.defaults(
            x: _marginX,
            y: y,
            width: 3,
            height: 24,
            zIndex: z++,
          ).copyWith(
            orientation: DividerOrientation.vertical,
            color: _primary,
            thickness: 3,
          ),
        );

        elements.add(
          TextElement.defaults(
            x: _marginX + 11,
            y: y,
            width: _contentW - 11,
            height: 24,
            zIndex: z++,
            content: section.heading,
          ).copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: _primary,
            letterSpacing: 0.3,
          ),
        );
        y += 32;
      }

      // Body
      if (bodyText.isNotEmpty) {
        elements.add(
          TextElement.defaults(
            x: _marginX,
            y: y,
            width: _contentW,
            height: bodyH,
            zIndex: z++,
            content: bodyText,
          ).copyWith(
            fontSize: 10,
            lineHeight: 1.55,
            color: _body,
          ),
        );
        y += bodyH + 10;
      }

      // Section divider
      elements.add(
        DividerElement.defaults(
          x: _marginX,
          y: y,
          width: _contentW,
          height: 1,
          zIndex: z++,
        ).copyWith(
          color: _border,
          thickness: 0.75,
        ),
      );
      y += 20;
    }

    return PdfDocumentData(
      name: 'SOW — $projectName',
      pageSize: PageSize.a4,
      elements: elements,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _buildBodyText(List<SowPdfItem> items) {
    final buf = StringBuffer();
    for (final item in items) {
      switch (item.type) {
        case SowPdfItemType.bullet:
          buf.writeln('\u2022 ${item.text}');
        case SowPdfItemType.numbered:
          buf.writeln(item.text);
        case SowPdfItemType.paragraph:
          buf.writeln(item.text);
      }
    }
    return buf.toString().trimRight();
  }

  static double _estimateHeight(String text) {
    if (text.trim().isEmpty) return 0;
    final lines = text.split('\n');
    int totalLines = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        totalLines += 1;
      } else {
        totalLines += (line.length / _charsPerLine).ceil().clamp(1, 50);
      }
    }
    return (totalLines * _bodyLineH).clamp(24.0, 800.0);
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
