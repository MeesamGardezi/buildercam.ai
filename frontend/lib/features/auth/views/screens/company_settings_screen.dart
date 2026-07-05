// Purpose: Lets the company owner manage company profile, trade categories and AI notes
// that are injected into every SOW and PDF generation request.
import 'package:buildercam/core/core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../services/auth_service.dart';

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _companyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  final _addCategoryController = TextEditingController();

  List<String> _categories = [];
  String _logoUrl = '';
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
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
    _companyNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
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
        _logoUrl = settings.logoUrl;
        _companyNameController.text = settings.companyName;
        _addressController.text = settings.address;
        _phoneController.text = settings.phone;
        _emailController.text = settings.email;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickAndUploadLogo() async {
    final auth = context.read<AuthController>();
    final companyId = auth.user?.companyId;
    if (companyId == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() => _uploadingLogo = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final ref = FirebaseStorage.instance
          .ref('companies/$companyId/logo.$ext');
      final metadata = SettableMetadata(
        contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
      );
      await ref.putData(bytes, metadata);
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logo upload failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
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
        logoUrl: _logoUrl,
        companyName: _companyNameController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
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
                  child: Center(
                    child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Company profile ──────────────────────────────────
                        Text(
                          'Company profile',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s1),
                        Text(
                          'Your logo and details are automatically filled into the default PDF template.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.bodyMuted,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s3),

                        // ── Logo upload ──────────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _LogoPreview(
                              logoUrl: _logoUrl,
                              uploading: _uploadingLogo,
                            ),
                            const SizedBox(width: AppSpacing.s3),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                                  icon: const Icon(Icons.upload_rounded, size: 16),
                                  label: Text(_logoUrl.isEmpty ? 'Upload logo' : 'Replace logo'),
                                ),
                                if (_logoUrl.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.s1),
                                  TextButton(
                                    onPressed: () => setState(() => _logoUrl = ''),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.danger,
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Remove logo'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s3),

                        // ── Company name ─────────────────────────────────────
                        TextField(
                          controller: _companyNameController,
                          decoration: AppInputs.standard(
                            labelText: 'Company name',
                            hintText: 'e.g. ABC Builders Pty Ltd',
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: AppSpacing.s3),

                        // ── Address ──────────────────────────────────────────
                        TextField(
                          controller: _addressController,
                          decoration: AppInputs.standard(
                            labelText: 'Address',
                            hintText: 'e.g. 123 Builder St, Sydney NSW 2000',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s3),

                        // ── Phone & email ────────────────────────────────────
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 480;
                            if (narrow) {
                              return Column(
                                children: [
                                  TextField(
                                    controller: _phoneController,
                                    decoration: AppInputs.standard(
                                      labelText: 'Phone',
                                      hintText: 'e.g. (02) 1234 5678',
                                    ),
                                    keyboardType: TextInputType.phone,
                                  ),
                                  const SizedBox(height: AppSpacing.s3),
                                  TextField(
                                    controller: _emailController,
                                    decoration: AppInputs.standard(
                                      labelText: 'Email',
                                      hintText: 'e.g. info@company.com.au',
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _phoneController,
                                    decoration: AppInputs.standard(
                                      labelText: 'Phone',
                                      hintText: 'e.g. (02) 1234 5678',
                                    ),
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s3),
                                Expanded(
                                  child: TextField(
                                    controller: _emailController,
                                    decoration: AppInputs.standard(
                                      labelText: 'Email',
                                      hintText: 'e.g. info@company.com.au',
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: AppSpacing.s6),
                        const Divider(),
                        const SizedBox(height: AppSpacing.s4),

                        // ── Section header ──────────────────────────────────
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

                        // ── Active categories ────────────────────────────────
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

                        // ── Add category input ───────────────────────────────
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

                        // ── Suggestions ──────────────────────────────────────
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

                        // ── AI notes ─────────────────────────────────────────
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

                        // ── Save button ──────────────────────────────────────
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
              ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({required this.logoUrl, required this.uploading});
  final String logoUrl;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd - 1),
        child: uploading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : logoUrl.isNotEmpty
                ? Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const _LogoPlaceholder(),
                  )
                : const _LogoPlaceholder(),
      ),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.business_rounded, color: AppColors.bodyMuted, size: 28),
        const SizedBox(height: 4),
        Text(
          'No logo',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.bodyMuted,
          ),
        ),
      ],
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
