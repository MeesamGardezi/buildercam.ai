// Purpose: Lets users configure preferences applied during SOW generation.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';

import '../../services/shared_prefs_service.dart';

class SowSettingsScreen extends StatefulWidget {
  const SowSettingsScreen({super.key});

  @override
  State<SowSettingsScreen> createState() => _SowSettingsScreenState();
}

class _SowSettingsScreenState extends State<SowSettingsScreen> {
  final _instructionsController = TextEditingController();
  final _notesController = TextEditingController();
  bool _includeMaterials = true;
  bool _includeEstimate = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await SowSharedPrefsService().loadSowSettings();
    if (!mounted) return;
    setState(() {
      _instructionsController.text = settings.specialInstructions;
      _notesController.text = settings.notes;
      _includeMaterials = settings.includeMaterials;
      _includeEstimate = settings.includeEstimate;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SowSharedPrefsService().saveSowSettings(
        SowSettings(
          specialInstructions: _instructionsController.text.trim(),
          notes: _notesController.text.trim(),
          includeMaterials: _includeMaterials,
          includeEstimate: _includeEstimate,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOW settings saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('SOW Settings'),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.s5),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Section header ──────────────────────────────────
                      Text(
                        'Generation preferences',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        'These settings are applied every time you generate a Scope of Work.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodyMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s5),

                      // ── Special instructions ─────────────────────────────
                      Text(
                        'Special instructions',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        'Custom directives sent to the AI — e.g. "Always include safety notes" or "Use metric units".',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodyMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      TextField(
                        controller: _instructionsController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: AppInputs.multiline(
                          labelText: 'Special instructions',
                          hintText:
                              'e.g. "Always add a safety section after Scope of Work."',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),

                      // ── Notes ────────────────────────────────────────────
                      Text('Notes', style: theme.textTheme.labelLarge),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        'Extra context or reminders appended to every SOW generation request.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodyMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      TextField(
                        controller: _notesController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: AppInputs.multiline(
                          labelText: 'Notes',
                          hintText:
                              'e.g. "Client prefers itemised cost per trade."',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s5),

                      // ── Include sections ─────────────────────────────────
                      Text(
                        'Sections to include',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        'Toggle which sections appear in the generated document.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodyMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s3),

                      _SettingsCheckboxTile(
                        title: 'Materials Required',
                        subtitle:
                            'List of materials with estimated quantities.',
                        value: _includeMaterials,
                        onChanged:
                            (v) => setState(() => _includeMaterials = v!),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      _SettingsCheckboxTile(
                        title: 'Labour Estimate',
                        subtitle: 'Tasks with estimated hours.',
                        value: _includeEstimate,
                        onChanged:
                            (v) => setState(() => _includeEstimate = v!),
                      ),
                      const SizedBox(height: AppSpacing.s6),

                      // ── Save button ──────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child:
                              _saving
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

class _SettingsCheckboxTile extends StatelessWidget {
  const _SettingsCheckboxTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: value ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.bodyMuted,
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
