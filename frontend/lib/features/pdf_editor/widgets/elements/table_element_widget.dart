import 'package:flutter/material.dart';

import '../../../../core/app_colors.dart';
import '../../models/template_element_model.dart';
import '../../providers/template_editor_provider.dart';

class TableElementWidget extends StatefulWidget {
  final TableElement element;
  final bool isEditing;
  final TemplateEditorProvider? provider;

  const TableElementWidget({
    super.key,
    required this.element,
    required this.isEditing,
    required this.provider,
  });

  @override
  State<TableElementWidget> createState() => _TableElementWidgetState();
}

class _TableElementWidgetState extends State<TableElementWidget> {
  // (row, col) — row -1 = header
  ({int row, int col})? _editingCell;
  late List<TextEditingController> _controllers;
  FocusNode? _cellFocusNode;
  final Set<FocusNode> _pendingFocusNodeDisposals = {};

  @override
  void initState() {
    super.initState();
    _buildControllers();
  }

  @override
  void didUpdateWidget(TableElementWidget old) {
    super.didUpdateWidget(old);
    if (widget.element.tableData != old.element.tableData) {
      for (final c in _controllers) {
        c.dispose();
      }
      _buildControllers();
    }
  }

  void _buildControllers() {
    final td = widget.element.tableData;
    final colCount = td.headers.length;
    _controllers = [
      ...td.headers.map((h) => TextEditingController(text: h)),
      for (final row in td.rows)
        for (var col = 0; col < colCount; col++)
          TextEditingController(text: col < row.length ? row[col] : ''),
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _disposeCellFocusNode(defer: false);
    for (final node in _pendingFocusNodeDisposals) {
      node.dispose();
    }
    _pendingFocusNodeDisposals.clear();
    super.dispose();
  }

  void _commitCell(int row, int col, String value) {
    final td = widget.element.tableData;
    TableData updated;
    if (row == -1) {
      if (col < 0 || col >= td.headers.length) return;
      final headers = [...td.headers];
      headers[col] = value;
      updated = td.copyWith(headers: headers);
    } else {
      if (row < 0 || row >= td.rows.length || col < 0) return;
      final rows = td.rows.map((r) => [...r]).toList();
      while (rows[row].length <= col) {
        rows[row].add('');
      }
      rows[row][col] = value;
      updated = td.copyWith(rows: rows);
    }
    _disposeCellFocusNode();
    if (mounted) {
      setState(() => _editingCell = null);
    } else {
      _editingCell = null;
    }
    widget.provider?.updateElement(widget.element.copyWith(tableData: updated));
  }

  void _beginEditingCell(int row, int col) {
    _selectTableElement();
    _disposeCellFocusNode();
    _cellFocusNode = FocusNode()
      ..addListener(() {
        if (_cellFocusNode?.hasFocus == false) {
          _commitActiveCell();
        }
      });

    setState(() => _editingCell = (row: row, col: col));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cellFocusNode?.requestFocus();
    });
  }

  void _commitActiveCell() {
    final active = _editingCell;
    if (active == null) return;
    final controller = _controllerFor(active.row, active.col);
    if (controller == null) return;
    _commitCell(active.row, active.col, controller.text);
  }

  void _disposeCellFocusNode({bool defer = true}) {
    final node = _cellFocusNode;
    _cellFocusNode = null;
    // Defer dispose: calling dispose() inside a FocusNode listener crashes
    // because the node is mid-notification when the listener fires _commitCell.
    if (node == null) return;
    if (!defer) {
      _pendingFocusNodeDisposals.remove(node);
      node.dispose();
      return;
    }
    _pendingFocusNodeDisposals.add(node);
    Future.microtask(() {
      if (!_pendingFocusNodeDisposals.remove(node)) return;
      node.dispose();
    });
  }

  void _selectTableElement() {
    widget.provider?.selectElement(widget.element.id);
  }

  TextEditingController? _controllerFor(int row, int col) {
    final colCount = widget.element.tableData.headers.length;
    final index = row == -1 ? col : colCount + row * colCount + col;
    if (index < 0 || index >= _controllers.length) return null;
    return _controllers[index];
  }

  String _cellValue(int row, int col) {
    final td = widget.element.tableData;
    if (row == -1) return td.headers[col];
    final cells = td.rows[row];
    return col < cells.length ? cells[col] : '';
  }

  @override
  Widget build(BuildContext context) {
    final el = widget.element;
    final td = el.tableData;
    final ts = el.tableStyle;

    final colCount = td.headers.length;
    if (colCount == 0) return const SizedBox.shrink();

    final totalRows = td.rows.length + 1;
    final rowHeight = el.height / totalRows;
    final maxPadding = rowHeight * 0.18;
    final padding = maxPadding < 2
        ? maxPadding.clamp(0.5, double.infinity).toDouble()
        : ts.cellPadding.clamp(2.0, maxPadding).toDouble();
    final headerFontSize = (rowHeight - padding * 2).clamp(8.0, 12.0).toDouble();
    final bodyFontSize = (rowHeight - padding * 2).clamp(7.0, 11.0).toDouble();

    return Column(
      children: [
        SizedBox(
          height: rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(colCount, (col) {
              return _cell(
                text: td.headers[col],
                controller: _controllers[col],
                row: -1,
                col: col,
                backgroundColor: ts.headerBg,
                borderColor: ts.borderColor,
                padding: padding,
                textColor: Colors.white,
                editingTextColor: Colors.white,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: headerFontSize,
                ),
              );
            }),
          ),
        ),
        for (int row = 0; row < td.rows.length; row++)
          SizedBox(
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(colCount, (col) {
                final ctrlIdx = colCount + row * colCount + col;
                return _cell(
                  text: _cellValue(row, col),
                  controller: ctrlIdx < _controllers.length
                      ? _controllers[ctrlIdx]
                      : null,
                  row: row,
                  col: col,
                  backgroundColor: ts.alternateRows && row.isOdd
                      ? ts.alternateRowColor
                      : Colors.white,
                  borderColor: ts.borderColor,
                  padding: padding,
                  textColor: AppColors.body,
                  editingTextColor: AppColors.body,
                  style: TextStyle(
                    color: AppColors.body,
                    fontSize: bodyFontSize,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _cell({
    required String text,
    required TextEditingController? controller,
    required int row,
    required int col,
    required TextStyle style,
    required Color textColor,
    required Color editingTextColor,
    required Color backgroundColor,
    required Color borderColor,
    required double padding,
  }) {
    final isActive = _editingCell != null &&
        _editingCell!.row == row &&
        _editingCell!.col == col;

    if (isActive && controller == null) {
      return const Expanded(child: SizedBox.shrink());
    }

    return Expanded(
      child: GestureDetector(
        onTap: _selectTableElement,
        onDoubleTap: () => _beginEditingCell(row, col),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor, width: 0.75),
          ),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: isActive
                ? TextSelectionTheme(
                    data: TextSelectionThemeData(
                      selectionColor:
                          editingTextColor.withValues(alpha: 0.35),
                      cursorColor: editingTextColor,
                      selectionHandleColor: editingTextColor,
                    ),
                    child: TextField(
                      controller: controller!,
                      focusNode: _cellFocusNode,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLines: null,
                      // Force text + cursor to stay visible against the cell bg
                      style: style.copyWith(color: editingTextColor),
                      cursorColor: editingTextColor,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (v) => _commitCell(row, col, v),
                      onEditingComplete: () =>
                          _commitCell(row, col, controller.text),
                      onTapOutside: (_) =>
                          _commitCell(row, col, controller.text),
                    ),
                  )
                : Text(
                    text,
                    style: style.copyWith(color: textColor),
                    softWrap: true,
                    overflow: TextOverflow.clip,
                  ),
          ),
        ),
      ),
    );
  }
}
