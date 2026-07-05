import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'element_type.dart';
import 'template_element_model.dart';
import 'template_model.dart';

/// The public input format for [PdfEditorWidget].
///
/// Pass an instance of this class to the widget. The editor populates
/// itself from [elements] and lets the user edit then download the PDF.
/// No persistence or network call is made — all saving is opt-in via
/// the parent software.
///
/// JSON shape:
/// ```json
/// {
///   "name": "My Document",          // optional — shown in toolbar
///   "pageSize": { "width": 595, "height": 842 },  // optional, A4 default
///   "elements": [ ... ]             // see element format below
/// }
/// ```
class PdfDocumentData {
  final String? name;
  final PageSize pageSize;
  final List<TemplateElement> elements;

  const PdfDocumentData({
    this.name,
    this.pageSize = PageSize.a4,
    required this.elements,
  });

  /// Empty document — blank A4 page, no elements.
  factory PdfDocumentData.empty({String? name}) => PdfDocumentData(
        name: name,
        pageSize: PageSize.a4,
        elements: const [],
      );

  /// Default template layout — A4 page with a professional header including
  /// logo placeholder, company info, date, divider, document title,
  /// client/project section, body placeholder, and signature block.
  ///
  /// Pass [companyName], [companyContact], and [logoUrl] to pre-fill the
  /// header with the company's saved profile information.
  static String _todayFormatted() {
    final now = DateTime.now();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  factory PdfDocumentData.withDefaultLayout({
    String? name,
    String? companyName,
    String? companyContact,
    String? logoUrl,
  }) {
    String newId() => const Uuid().v4().substring(0, 8);
    return PdfDocumentData(
      name: name,
      pageSize: PageSize.a4,
      elements: [
        // ── Header: logo (left) + company info (centre-left) + date (right) ──
        LogoElement(
          id: newId(),
          x: 30, y: 24, width: 110, height: 55,
          zIndex: 1, locked: false, visible: true,
          src: logoUrl ?? '', opacity: 1.0,
        ),
        TextElement(
          id: newId(),
          x: 152, y: 24, width: 260, height: 28,
          zIndex: 2, locked: false, visible: true,
          content: companyName?.isNotEmpty == true ? companyName! : 'Your Company Name',
          fontFamily: 'Roboto',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF0F172A),
          textAlign: TextAlign.left,
          lineHeight: 1.3,
          letterSpacing: 0,
        ),
        TextElement(
          id: newId(),
          x: 152, y: 54, width: 260, height: 28,
          zIndex: 2, locked: false, visible: true,
          content: companyContact?.isNotEmpty == true
              ? companyContact!
              : '123 Builder Street, Sydney NSW 2000\ninfo@company.com.au  |  (02) 1234 5678',
          fontFamily: 'Roboto',
          fontSize: 9,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF64748B),
          textAlign: TextAlign.left,
          lineHeight: 1.5,
          letterSpacing: 0,
        ),
        TextElement(
          id: newId(),
          x: 432, y: 24, width: 133, height: 18,
          zIndex: 2, locked: false, visible: true,
          content: 'DATE',
          fontFamily: 'Roboto',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF0284C7),
          textAlign: TextAlign.right,
          lineHeight: 1.4,
          letterSpacing: 0.8,
        ),
        TextElement(
          id: newId(),
          x: 432, y: 40, width: 133, height: 18,
          zIndex: 2, locked: false, visible: true,
          content: _todayFormatted(),
          fontFamily: 'Roboto',
          fontSize: 10,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF475569),
          textAlign: TextAlign.right,
          lineHeight: 1.4,
          letterSpacing: 0,
        ),
        TextElement(
          id: newId(),
          x: 432, y: 60, width: 133, height: 18,
          zIndex: 2, locked: false, visible: true,
          content: 'REF: #0001',
          fontFamily: 'Roboto',
          fontSize: 9,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF94A3B8),
          textAlign: TextAlign.right,
          lineHeight: 1.4,
          letterSpacing: 0,
        ),
        // ── Accent divider ────────────────────────────────────────────────────
        DividerElement(
          id: newId(),
          x: 30, y: 92, width: 535, height: 3,
          zIndex: 1, locked: false, visible: true,
          orientation: DividerOrientation.horizontal,
          thickness: 2,
          color: const Color(0xFF0284C7),
          dashStyle: DividerDashStyle.solid,
        ),
        // ── Document title ────────────────────────────────────────────────────
        TextElement(
          id: newId(),
          x: 30, y: 106, width: 535, height: 36,
          zIndex: 2, locked: false, visible: true,
          content: 'DOCUMENT TITLE',
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF0F172A),
          textAlign: TextAlign.center,
          lineHeight: 1.3,
          letterSpacing: 2,
        ),
        // ── Prepared for / Project details ────────────────────────────────────
        TextElement(
          id: newId(),
          x: 30, y: 156, width: 120, height: 16,
          zIndex: 2, locked: false, visible: true,
          content: 'PREPARED FOR',
          fontFamily: 'Roboto',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF0284C7),
          textAlign: TextAlign.left,
          lineHeight: 1.4,
          letterSpacing: 0.8,
        ),
        TextElement(
          id: newId(),
          x: 30, y: 174, width: 250, height: 22,
          zIndex: 2, locked: false, visible: true,
          content: 'Client Name',
          fontFamily: 'Roboto',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF0F172A),
          textAlign: TextAlign.left,
          lineHeight: 1.3,
          letterSpacing: 0,
        ),
        TextElement(
          id: newId(),
          x: 30, y: 198, width: 250, height: 52,
          zIndex: 2, locked: false, visible: true,
          content: 'Client Address\nCity, State  Postcode\nclient@email.com',
          fontFamily: 'Roboto',
          fontSize: 10,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF475569),
          textAlign: TextAlign.left,
          lineHeight: 1.6,
          letterSpacing: 0,
        ),
        TextElement(
          id: newId(),
          x: 340, y: 156, width: 225, height: 16,
          zIndex: 2, locked: false, visible: true,
          content: 'PROJECT DETAILS',
          fontFamily: 'Roboto',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF0284C7),
          textAlign: TextAlign.left,
          lineHeight: 1.4,
          letterSpacing: 0.8,
        ),
        TextElement(
          id: newId(),
          x: 340, y: 174, width: 225, height: 76,
          zIndex: 2, locked: false, visible: true,
          content: 'Project: Project Name\nLocation: Site Address\nLicence No: XXXXXXX',
          fontFamily: 'Roboto',
          fontSize: 10,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF475569),
          textAlign: TextAlign.left,
          lineHeight: 1.6,
          letterSpacing: 0,
        ),
        // ── Body section divider ──────────────────────────────────────────────
        DividerElement(
          id: newId(),
          x: 30, y: 258, width: 535, height: 2,
          zIndex: 1, locked: false, visible: true,
          orientation: DividerOrientation.horizontal,
          thickness: 1,
          color: const Color(0xFFCBD5E1),
          dashStyle: DividerDashStyle.solid,
        ),
        // ── Body placeholder ──────────────────────────────────────────────────
        TextElement(
          id: newId(),
          x: 30, y: 272, width: 535, height: 56,
          zIndex: 2, locked: false, visible: true,
          content: 'Description of work to be performed. Add your scope, terms, and any relevant notes here.',
          fontFamily: 'Roboto',
          fontSize: 11,
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
          color: const Color(0xFF64748B),
          textAlign: TextAlign.left,
          lineHeight: 1.6,
          letterSpacing: 0,
        ),
        // ── Signature block ───────────────────────────────────────────────────
        SignatureBlockElement(
          id: newId(),
          x: 30, y: 748, width: 240, height: 62,
          zIndex: 2, locked: false, visible: true,
          signatureLabel: 'Authorised Signature',
          dateLabel: 'Date',
        ),
      ],
    );
  }

  factory PdfDocumentData.fromJson(Map<String, dynamic> json) {
    final rawElements = json['elements'];
    final elements = <TemplateElement>[];
    if (rawElements is List) {
      for (final e in rawElements) {
        try {
          elements.add(TemplateElement.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map),
          ));
        } catch (err) {
          // ignore: avoid_print
          print('[PdfDocumentData] skipped element: $err');
        }
      }
    }

    return PdfDocumentData(
      name: json['name']?.toString(),
      pageSize: json['pageSize'] != null
          ? PageSize.fromJson(
              Map<String, dynamic>.from(json['pageSize'] as Map))
          : PageSize.a4,
      elements: elements,
    );
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        'pageSize': pageSize.toJson(),
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  /// Converts to the internal [TemplateModel] used by the editor.
  /// A UUID is generated automatically — the parent software does not
  /// need to supply one.
  TemplateModel toTemplateModel() => TemplateModel(
        id: const Uuid().v4(),
        name: name ?? 'Document',
        type: TemplateType.custom,
        isPreset: false,
        pageSize: pageSize,
        elements: elements,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: '',
      );
}
