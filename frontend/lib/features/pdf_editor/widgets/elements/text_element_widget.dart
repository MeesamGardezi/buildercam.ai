import 'package:flutter/material.dart';

import '../../models/template_element_model.dart';

class TextElementWidget extends StatefulWidget {
  final TextElement element;
  final bool isEditing;
  final void Function(String text) onCommit;

  const TextElementWidget({
    super.key,
    required this.element,
    required this.isEditing,
    required this.onCommit,
  });

  @override
  State<TextElementWidget> createState() => _TextElementWidgetState();
}

class _TextElementWidgetState extends State<TextElementWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  late String _lastCommittedText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.element.content);
    _focusNode = FocusNode();
    _lastCommittedText = widget.element.content;
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && widget.isEditing) {
        _commitIfNeeded();
      }
    });
  }

  @override
  void didUpdateWidget(TextElementWidget old) {
    super.didUpdateWidget(old);
    if (widget.isEditing && !old.isEditing) {
      _controller.text = widget.element.content;
      _lastCommittedText = widget.element.content;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
    }
    if (!widget.isEditing && old.isEditing) {
      _commitIfNeeded();
    }
    if (!widget.isEditing && widget.element.content != _controller.text) {
      _controller.text = widget.element.content;
      _lastCommittedText = widget.element.content;
    }
  }

  @override
  void dispose() {
    if (widget.isEditing) {
      _commitIfNeeded();
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commitIfNeeded() {
    final nextText = _controller.text;
    if (_lastCommittedText == nextText) return;
    _lastCommittedText = nextText;
    widget.onCommit(nextText);
  }

  @override
  Widget build(BuildContext context) {
    final el = widget.element;

    if (widget.isEditing) {
      return Container(
        color: el.backgroundColor,
        child: TextSelectionTheme(
          data: TextSelectionThemeData(
            selectionColor: el.color.withValues(alpha: 0.35),
            cursorColor: el.color,
            selectionHandleColor: el.color,
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            maxLines: null,
            expands: true,
            textAlign: el.textAlign,
            style: _buildStyle(el),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            onEditingComplete: _commitIfNeeded,
            onTapOutside: (_) {
              _commitIfNeeded();
              _focusNode.unfocus();
            },
          ),
        ),
      );
    }

    return Container(
      alignment: _alignmentFor(el.textAlign),
      color: el.backgroundColor,
      child: Text(
        el.content,
        textAlign: el.textAlign,
        style: _buildStyle(el),
        softWrap: true,
        overflow: TextOverflow.clip,
      ),
    );
  }

  TextStyle _buildStyle(TextElement el) {
    TextDecoration? decoration;
    if (el.underline && el.strikethrough) {
      decoration = TextDecoration.combine(
          [TextDecoration.underline, TextDecoration.lineThrough]);
    } else if (el.underline) {
      decoration = TextDecoration.underline;
    } else if (el.strikethrough) {
      decoration = TextDecoration.lineThrough;
    }
    return TextStyle(
      fontFamily: el.fontFamily,
      fontSize: el.fontSize,
      fontWeight: el.fontWeight,
      fontStyle: el.fontStyle,
      color: el.color,
      height: el.lineHeight,
      letterSpacing: el.letterSpacing,
      decoration: decoration,
      decorationColor: el.color,
    );
  }

  Alignment _alignmentFor(TextAlign align) => switch (align) {
        TextAlign.left || TextAlign.start => Alignment.centerLeft,
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        TextAlign.justify => Alignment.centerLeft,
      };
}
