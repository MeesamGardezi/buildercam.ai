// Purpose: Lets the company owner manage trade categories and AI notes
// that are injected into every SOW and PDF generation request.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../services/auth_service.dart';

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _notesController = TextEditingController();
  final _addCategoryController = TextEditingController();

  List<String> _categories = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const List<String> _suggestions = [
    'Plumbing',
    'Electrical',
    'HVAC',
    'Plaster',
    'Insulation',
    'Carpentry',
    'Painting',
    'Roofing',
    'Flooring',
    'Tiling',
    'Concrete',
    'Framing',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthController>();
      if (auth.user?.isOwner != true) {
        context.pop();
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _addCategoryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthController>();
      final token = await auth.getIdToken();
      if (token == null) throw Exception('Not authenticated.');
      final settings = await AuthService().fetchCompanySettings(token);
      if (!mounted) return;
      setState(() {
        _categories = List<String>.from(settings.categories);
        _notesController.text = settings.notes;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthController>();
      final token = await auth.getIdToken();
      if (token == null) throw Exception('Not authenticated.');
      await AuthService().updateCompanySettings(
        categories: _categories,
        notes: _notesController.text.trim(),
        idToken: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Company settings saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addCategory(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (_categories.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    setState(() => _categories.add(trimmed));
    _addCategoryController.clear();
  }

  void _removeCategory(String category) {
    setState(() => _categories.remove(category));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Company Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(error: _error!, onRetry: _load)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.s5),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Section header ──────────────────────────────
                        Text(
                          'Trade categories',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s1),
                        Text(
                          'Add the trades relevant to your company. The AI will organise every SOW and PDF under these categories.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.bodyMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s3),

                        // ── Active categories ────────────────────────────
                        if (_categories.isNotEmpty) ...[
                          Wrap(
                            spacing: AppSpacing.s2,
                            runSpacing: AppSpacing.s2,
                            children: _categories
                                .map(
                                  (cat) => Chip(
                                    label: Text(cat),
                                    deleteIcon: const Icon(Icons.close, size: 16),
                                    onDeleted: () => _removeCategory(cat),
                                    backgroundColor: AppColors.blue100,
                                    labelStyle: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    deleteIconColor: AppColors.primary,
                                    side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: AppSpacing.s3),
                        ],

                        // ── Add category input ───────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _addCategoryController,
                                decoration: AppInputs.standard(
                                  labelText: 'Add category',
                                  hintText: 'e.g. Plumbing',
                                ),
                                onSubmitted: _addCategory,
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s2),
                            FilledButton(
                              onPressed: () =>
                                  _addCategory(_addCategoryController.text),
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s3),

                        // ── Suggestions ──────────────────────────────────
                        Text(
                          'Suggestions',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.bodyMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        Wrap(
                          spacing: AppSpacing.s2,
                          runSpacing: AppSpacing.s2,
                          children: _suggestions
                              .where((s) => !_categories.any(
                                    (c) => c.toLowerCase() == s.toLowerCase(),
                                  ))
                              .map(
                                (s) => ActionChip(
                                  label: Text(s),
                                  avatar: const Icon(Icons.add, size: 16),
                                  onPressed: () => _addCategory(s),
                                  side: BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                  ),
                                ),
                              )
                              .toList(),
                        ),

                        const SizedBox(height: AppSpacing.s6),
                        const Divider(),
                        const SizedBox(height: AppSpacing.s4),

                        // ── AI notes ─────────────────────────────────────
                        Text(
                          'AI notes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s1),
                        Text(
                          'Additional context sent to the AI alongside every generation request — e.g. preferred formats, exclusions, or company-specific rules.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.bodyMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s2),
                        TextField(
                          controller: _notesController,
                          minLines: 4,
                          maxLines: 8,
                          decoration: AppInputs.multiline(
                            labelText: 'Notes',
                            hintText:
                                'e.g. "Always list safety requirements per trade."',
                          ),
                        ),

                        const SizedBox(height: AppSpacing.s6),

                        // ── Save button ──────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Save settings'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
            const SizedBox(height: AppSpacing.s3),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s4),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
