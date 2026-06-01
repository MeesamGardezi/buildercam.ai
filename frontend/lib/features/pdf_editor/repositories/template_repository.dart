import '../models/element_type.dart';
import '../models/template_model.dart';

/// Abstract contract for all template persistence operations.
/// Widgets and providers only depend on this interface — never on Firestore directly.
abstract class TemplateRepository {
  /// Fetches a single page of templates (limit 20) for a company.
  /// Pass [cursor] to paginate.
  Future<TemplatePageResult> fetchTemplates(
    String companyId, {
    TemplateType? type,
    Object? cursor,
  });

  /// Fetches a single template by ID.
  Future<TemplateModel?> fetchTemplate(String companyId, String templateId);

  /// Creates a new template document and returns it with the server-assigned ID.
  Future<TemplateModel> createTemplate(String companyId, TemplateModel template);

  /// Writes the full template document (used on save).
  Future<void> updateTemplate(String companyId, TemplateModel template);

  /// Hard-deletes a template document and its Storage assets.
  Future<void> deleteTemplate(String companyId, String templateId);

  /// Real-time stream used on the home dashboard list only.
  Stream<List<TemplateModel>> watchTemplates(String companyId, {TemplateType? type});

  /// Returns all preset templates (fetched once, caller should cache).
  Future<List<TemplateModel>> fetchPresetTemplates();

  /// Duplicates a template with a new name and returns the copy.
  Future<TemplateModel> duplicateTemplate(
    String companyId,
    String templateId,
    String newName,
  );

  /// Renames a template in-place.
  Future<void> renameTemplate(String companyId, String templateId, String name);
}

class TemplatePageResult {
  final List<TemplateModel> items;

  /// Opaque Firestore cursor for the next page; null when no more pages.
  final Object? nextCursor;

  const TemplatePageResult({required this.items, this.nextCursor});

  bool get hasMore => nextCursor != null;
}
