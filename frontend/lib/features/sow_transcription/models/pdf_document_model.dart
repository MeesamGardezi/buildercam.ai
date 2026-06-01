// Purpose: Data model for a standalone PDF document stored under a project.
import 'package:buildercam/features/pdf_editor/models/pdf_document_data.dart';

class PdfDocumentModel {
  const PdfDocumentModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.pdfData,
    required this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final String title;
  final Map<String, dynamic> pdfData;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PdfDocumentModel.fromJson(Map<String, dynamic> json) {
    return PdfDocumentModel(
      id: json['id']?.toString() ?? '',
      projectId: json['projectId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled PDF',
      pdfData: json['pdfData'] is Map<String, dynamic>
          ? json['pdfData'] as Map<String, dynamic>
          : json['pdfData'] is Map
              ? Map<String, dynamic>.from(json['pdfData'] as Map)
              : const {},
      createdBy: json['createdBy']?.toString() ?? '',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  /// Converts stored [pdfData] into a [PdfDocumentData] for the editor.
  PdfDocumentData toPdfDocumentData() {
    if (pdfData.isEmpty) return PdfDocumentData.empty(name: title);
    return PdfDocumentData.fromJson(pdfData);
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
