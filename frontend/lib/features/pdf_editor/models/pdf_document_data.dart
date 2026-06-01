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
