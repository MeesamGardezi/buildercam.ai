import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/template_element_model.dart';

enum _SignatureField {
  signatureLabel,
  signatureValue,
  dateLabel,
  dateValue,
}

class SignatureBlockWidget extends StatefulWidget {
  final SignatureBlockElement element;
  final bool isSelected;
  final ValueChanged<SignatureBlockElement> onChanged;
  final VoidCallback? onSelect;
  final VoidCallback? onBeginEdit;
  final VoidCallback? onEndEdit;

  const SignatureBlockWidget({
    super.key,
    required this.element,
    required this.isSelected,
    required this.onChanged,
    this.onSelect,
    this.onBeginEdit,
    this.onEndEdit,
  });

  @override
  State<SignatureBlockWidget> createState() => _SignatureBlockWidgetState();
}

class _SignatureBlockWidgetState extends State<SignatureBlockWidget> {
  _SignatureField? _editingField;
  late final TextEditingController _signatureLabel;
  late final TextEditingController _signatureValue;
  late final TextEditingController _dateLabel;
  late final TextEditingController _dateValue;
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _signatureLabel =
        TextEditingController(text: widget.element.signatureLabel);
    _signatureValue =
        TextEditingController(text: widget.element.signatureValue);
    _dateLabel = TextEditingController(text: widget.element.dateLabel);
    _dateValue = TextEditingController(text: widget.element.dateValue);
  }

  @override
  void didUpdateWidget(SignatureBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editingField != null) return;
    _signatureLabel.text = widget.element.signatureLabel;
    _signatureValue.text = widget.element.signatureValue;
    _dateLabel.text = widget.element.dateLabel;
    _dateValue.text = widget.element.dateValue;
  }

  @override
  void dispose() {
    _commitEditing(fromDispose: true);
    _signatureLabel.dispose();
    _signatureValue.dispose();
    _dateLabel.dispose();
    _dateValue.dispose();
    _disposeFocusNode();
    super.dispose();
  }

  void _disposeFocusNode() {
    _focusNode?.dispose();
    _focusNode = null;
  }

  TextEditingController _controllerFor(_SignatureField field) =>
      switch (field) {
        _SignatureField.signatureLabel => _signatureLabel,
        _SignatureField.signatureValue => _signatureValue,
        _SignatureField.dateLabel => _dateLabel,
        _SignatureField.dateValue => _dateValue,
      };

  void _handleTap() {
    widget.onSelect?.call();
  }

  void _startEditing(_SignatureField field) {
    if (widget.element.locked) return;
    // Select first (no-op if already selected), then always enter edit mode.
    // Checking widget.isSelected here races the provider rebuild — skip it.
    widget.onSelect?.call();
    widget.onBeginEdit?.call();

    _disposeFocusNode();
    _focusNode = FocusNode()
      ..addListener(() {
        if (_focusNode?.hasFocus == false) {
          _commitEditing();
        }
      });

    setState(() => _editingField = field);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode?.requestFocus();
      final ctrl = _controllerFor(field);
      ctrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: ctrl.text.length,
      );
    });
  }

  void _commitEditing({bool fromDispose = false}) {
    final field = _editingField;
    if (field == null) return;

    final ctrl = _controllerFor(field);
    final raw = ctrl.text.trim();
    var updated = widget.element;

    switch (field) {
      case _SignatureField.signatureLabel:
        final label = raw.isEmpty ? 'Signature' : raw;
        if (ctrl.text != label) ctrl.text = label;
        updated = updated.copyWith(signatureLabel: label);
        break;
      case _SignatureField.signatureValue:
        updated = updated.copyWith(signatureValue: raw);
        break;
      case _SignatureField.dateLabel:
        final label = raw.isEmpty ? 'Date' : raw;
        if (ctrl.text != label) ctrl.text = label;
        updated = updated.copyWith(dateLabel: label);
        break;
      case _SignatureField.dateValue:
        updated = updated.copyWith(dateValue: raw);
        break;
    }

    _disposeFocusNode();
    _editingField = null;

    if (fromDispose) {
      // notifyListeners() during dispose crashes (tree is locked).
      // Capture callbacks before the frame so they're safe to call later.
      final onChanged = widget.onChanged;
      final onEndEdit = widget.onEndEdit;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(updated);
        onEndEdit?.call();
      });
    } else {
      widget.onChanged(updated);
      widget.onEndEdit?.call();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelSignature = widget.element.signatureLabel.trim().isEmpty
        ? 'Signature'
        : widget.element.signatureLabel;
    final labelDate = widget.element.dateLabel.trim().isEmpty
        ? 'Date'
        : widget.element.dateLabel;

    return SizedBox(
      width: widget.element.width,
      height: widget.element.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildRow(
            labelField: _SignatureField.signatureLabel,
            labelText: labelSignature,
            valueField: _SignatureField.signatureValue,
            valueText: widget.element.signatureValue,
          ),
          const SizedBox(height: 8),
          _buildRow(
            labelField: _SignatureField.dateLabel,
            labelText: labelDate,
            valueField: _SignatureField.dateValue,
            valueText: widget.element.dateValue,
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required _SignatureField labelField,
    required String labelText,
    required _SignatureField valueField,
    required String valueText,
  }) {
    return Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: _buildEditableLabel(labelField, labelText),
        ),
        const Text(
          ': ',
          style: TextStyle(fontSize: 11, color: AppColors.bodyMuted),
        ),
        Expanded(child: _buildEditableValue(valueField, valueText)),
      ],
    );
  }

  Widget _buildEditableLabel(_SignatureField field, String text) {
    final isEditing = _editingField == field;
    if (isEditing) {
      return TextField(
        controller: _controllerFor(field),
        focusNode: _focusNode,
        textInputAction: TextInputAction.done,
        maxLines: 1,
        style: const TextStyle(fontSize: 11, color: AppColors.bodyMuted),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (_) => _commitEditing(),
        onEditingComplete: _commitEditing,
        onTapOutside: (_) => _commitEditing(),
      );
    }

    return GestureDetector(
      onTap: _handleTap,
      onDoubleTap: () => _startEditing(field),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppColors.bodyMuted),
      ),
    );
  }

  Widget _buildEditableValue(_SignatureField field, String value) {
    final isEditing = _editingField == field;
    if (isEditing) {
      return TextField(
        controller: _controllerFor(field),
        focusNode: _focusNode,
        textInputAction: TextInputAction.done,
        maxLines: 1,
        style: const TextStyle(fontSize: 11, color: AppColors.body),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (_) => _commitEditing(),
        onEditingComplete: _commitEditing,
        onTapOutside: (_) => _commitEditing(),
      );
    }

    return GestureDetector(
      onTap: _handleTap,
      onDoubleTap: () => _startEditing(field),
      child: _LineValue(value: value),
    );
  }
}

class _LineValue extends StatelessWidget {
  final String value;

  const _LineValue({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.trim().isNotEmpty) {
      return Text(
        value,
        style: const TextStyle(fontSize: 11, color: AppColors.body),
        overflow: TextOverflow.clip,
      );
    }

    return Container(
      height: 1,
      color: AppColors.charcoal400,
      margin: const EdgeInsets.only(bottom: 2),
    );
  }
}
