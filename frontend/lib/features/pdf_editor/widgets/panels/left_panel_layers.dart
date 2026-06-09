import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../models/template_element_model.dart';
import '../../providers/template_editor_provider.dart';

/// Figma-style layers panel. Shows all elements in ascending z-index order
/// (backmost element at the top of the list). Each row shows element icon,
/// name, visibility toggle, and lock toggle.
///
/// Table and SignatureBlock rows expand inline to show their child
/// fields without affecting the drag-reorder order.
class LeftPanelLayers extends StatefulWidget {
  const LeftPanelLayers({super.key});

  @override
  State<LeftPanelLayers> createState() => _LeftPanelLayersState();
}

class _LeftPanelLayersState extends State<LeftPanelLayers> {
  // IDs of layer rows the user has expanded (table / signature).
  final Set<String> _expanded = {};

  void _toggleExpanded(String id) => setState(
      () => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Layers',
            action: _AddElementMenuButton(
              onSelect: (build) {
                final provider = context.read<TemplateEditorProvider>();
                provider.addElement(build());
              },
            ),
          ),
          Expanded(
            child: Consumer<TemplateEditorProvider>(
              builder: (context, provider, _) {
                // Ascending z-index: index 0 = backmost, last = frontmost.
                final layers = provider.sortedElements;

                if (layers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers_outlined,
                              size: 32,
                              color: AppColors.bodySubtle
                                  .withValues(alpha: 0.6)),
                          const SizedBox(height: AppSpacing.s3),
                          const Text(
                            'No elements yet',
                            style: TextStyle(
                              color: AppColors.body,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap + to add your first element',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.bodyMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s2,
                  ),
                  itemCount: layers.length,
                  onReorder: (oldIdx, newIdx) =>
                      _onReorder(provider, layers, oldIdx, newIdx),
                  itemBuilder: (context, idx) {
                    final el = layers[idx];
                    final isExpanded = _expanded.contains(el.id);
                    return _buildLayerItem(
                      key: ValueKey(el.id),
                      context: context,
                      idx: idx,
                      el: el,
                      provider: provider,
                      isExpanded: isExpanded,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerItem({
    required Key key,
    required BuildContext context,
    required int idx,
    required TemplateElement el,
    required TemplateEditorProvider provider,
    required bool isExpanded,
  }) {
    final hasChildren = el is TableElement || el is SignatureBlockElement;

    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LayerRow(
          index: idx,
          element: el,
          isSelected: provider.isSelected(el.id),
          hasChildren: hasChildren,
          isExpanded: isExpanded,
          onTap: () => provider.selectElement(el.id, focus: true),
          onExpandToggle: hasChildren ? () => _toggleExpanded(el.id) : null,
          onVisibilityToggle: () => provider.toggleVisibility(el.id),
          onLockToggle: () => provider.toggleLock(el.id),
        ),
        if (isExpanded && el is TableElement)
          _TableChildren(
            table: el,
            isSelected: provider.isSelected(el.id),
          ),
        if (isExpanded && el is SignatureBlockElement)
          _SignatureChildren(
            element: el,
            isSelected: provider.isSelected(el.id),
          ),
      ],
    );
  }

  void _onReorder(
    TemplateEditorProvider provider,
    List<TemplateElement> layers,
    int oldIdx,
    int newIdx,
  ) {
    if (newIdx > oldIdx) newIdx--;
    final reordered = [...layers];
    final moved = reordered.removeAt(oldIdx);
    reordered.insert(newIdx, moved);
    // Batch all z-index updates in one undo state via the dedicated method.
    provider.reorderLayers(reordered.map((e) => e.id).toList());
  }

}

// ── Panel header ──────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const _PanelHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.6,
                color: AppColors.bodyMuted,
              ),
            ),
            const Spacer(),
            if (action != null) action!,
          ],
        ),
      );
}

// ── Layer row ─────────────────────────────────────────────────────────────────

class _LayerRow extends StatefulWidget {
  final int index;
  final TemplateElement element;
  final bool isSelected;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onExpandToggle;
  final VoidCallback onVisibilityToggle;
  final VoidCallback onLockToggle;

  const _LayerRow({
    required this.index,
    required this.element,
    required this.isSelected,
    required this.hasChildren,
    required this.isExpanded,
    required this.onTap,
    required this.onExpandToggle,
    required this.onVisibilityToggle,
    required this.onLockToggle,
  });

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final el = widget.element;
    final showActions = _hover || widget.isSelected || !el.visible || el.locked;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.only(left: 4, right: 4),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.primaryLight
                : (_hover ? AppColors.surfaceRaised : Colors.transparent),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hover ? 1.0 : 0.0,
                child: ReorderableDragStartListener(
                  index: widget.index,
                  child: const SizedBox(
                    width: 16,
                    height: 28,
                    child: Icon(Icons.drag_indicator,
                        size: 14, color: AppColors.bodySubtle),
                  ),
                ),
              ),
              if (widget.hasChildren)
                GestureDetector(
                  onTap: widget.onExpandToggle,
                  child: AnimatedRotation(
                    turns: widget.isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.chevron_right,
                          size: 14, color: AppColors.bodyMuted),
                    ),
                  ),
                )
              else
                const SizedBox(width: 18),
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  el.type.icon,
                  size: 12,
                  color: widget.isSelected
                      ? AppColors.primary
                      : AppColors.bodyMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  _label(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: el.visible
                        ? (widget.isSelected
                            ? AppColors.primaryDark
                            : AppColors.body)
                        : AppColors.bodySubtle,
                    fontStyle:
                        el.visible ? FontStyle.normal : FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: showActions ? 1.0 : 0.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SmallIconBtn(
                      icon: el.visible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_rounded,
                      onTap: widget.onVisibilityToggle,
                      tooltip: el.visible ? 'Hide' : 'Show',
                      active: !el.visible,
                    ),
                    _SmallIconBtn(
                      icon: el.locked
                          ? Icons.lock_rounded
                          : Icons.lock_open_outlined,
                      onTap: widget.onLockToggle,
                      tooltip: el.locked ? 'Unlock' : 'Lock',
                      active: el.locked,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label() => switch (widget.element) {
        TextElement te =>
          te.content.trim().isEmpty ? 'Text' : te.content.replaceAll('\n', ' '),
        ImageElement _ => 'Image',
        TableElement _ => 'Table',
        LogoElement _ => 'Logo',
        SignatureBlockElement _ => 'Signature Block',
        DividerElement _ => 'Divider',
        ShapeElement se => '${se.shapeKind.name[0].toUpperCase()}${se.shapeKind.name.substring(1)}',
        ContainerElement _ => 'Container',
      };
}

// ── Table children ────────────────────────────────────────────────────────────

class _TableChildren extends StatelessWidget {
  final TableElement table;
  final bool isSelected;

  const _TableChildren({
    required this.table,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TemplateEditorProvider>();
    final td = table.tableData;
    final children = <Widget>[];

    // Header cells
    for (int i = 0; i < td.headers.length; i++) {
      children.add(_ChildRow(
        icon: Icons.title,
        label: td.headers[i].isEmpty ? 'Header ${i + 1}' : td.headers[i],
        isHeader: true,
        isSelected: isSelected,
        onTap: () => provider.selectElement(table.id, focus: true),
      ));
    }

    // Data rows — each row shown as one entry previewing the first two cells
    for (int r = 0; r < td.rows.length; r++) {
      final row = td.rows[r];
      final preview = row.where((c) => c.trim().isNotEmpty).take(2).join(' · ');
      children.add(_ChildRow(
        icon: Icons.table_rows_outlined,
        label: preview.isEmpty ? 'Row ${r + 1}' : preview,
        isHeader: false,
        isSelected: isSelected,
        onTap: () => provider.selectElement(table.id, focus: true),
      ));
    }

    if (children.isEmpty) {
      children.add(_ChildRow(
        icon: Icons.grid_off_outlined,
        label: 'Empty table',
        isHeader: false,
        isSelected: isSelected,
        onTap: () => provider.selectElement(table.id, focus: true),
      ));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

// ── Signature children ────────────────────────────────────────────────────────

class _SignatureChildren extends StatelessWidget {
  final SignatureBlockElement element;
  final bool isSelected;

  const _SignatureChildren({
    required this.element,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TemplateEditorProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChildRow(
          icon: Icons.draw_outlined,
          label:
              '${element.signatureLabel}: ${element.signatureValue.isEmpty ? '___________' : element.signatureValue}',
          isHeader: false,
          isSelected: isSelected,
          onTap: () => provider.selectElement(element.id, focus: true),
        ),
        _ChildRow(
          icon: Icons.calendar_today_outlined,
          label:
              '${element.dateLabel}: ${element.dateValue.isEmpty ? '___________' : element.dateValue}',
          isHeader: false,
          isSelected: isSelected,
          onTap: () => provider.selectElement(element.id, focus: true),
        ),
      ],
    );
  }
}

// ── Shared child row ──────────────────────────────────────────────────────────

class _ChildRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isHeader;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChildRow({
    required this.icon,
    required this.label,
    required this.isHeader,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.only(
            left: AppSpacing.s6 + 18,
            right: AppSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryLight.withValues(alpha: 0.22)
                : const Color(0xFFF8FAFC),
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
              bottom: const BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: AppColors.bodySubtle),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        isHeader ? AppColors.primaryDark : AppColors.bodyMuted,
                    fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Small icon button ─────────────────────────────────────────────────────────

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  const _SmallIconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: Icon(
                icon,
                size: 13,
                color: active ? AppColors.primary : AppColors.bodyMuted,
              ),
            ),
          ),
        ),
      );
}

// ── Add element menu ──────────────────────────────────────────────────────────

typedef _ElementBuilder = TemplateElement Function();

class _AddElementMenuButton extends StatelessWidget {
  final ValueChanged<_ElementBuilder> onSelect;

  const _AddElementMenuButton({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final entries = <(_ElementBuilder, String, IconData)>[
      (TextElement.defaults, 'Text', Icons.text_fields),
      (ImageElement.defaults, 'Image', Icons.image_outlined),
      (TableElement.defaults, 'Table', Icons.table_chart_outlined),
      (LogoElement.defaults, 'Logo', Icons.business_outlined),
      (SignatureBlockElement.defaults, 'Signature Block', Icons.draw_outlined),
      (DividerElement.defaults, 'Divider', Icons.horizontal_rule),
      (ShapeElement.defaults, 'Shape', Icons.crop_square_outlined),
      (ContainerElement.defaults, 'Container', Icons.web_asset_outlined),
    ];

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      menuChildren: [
        for (final (builder, label, icon) in entries)
          MenuItemButton(
            leadingIcon: Icon(icon, size: 16, color: AppColors.primary),
            onPressed: () => onSelect(builder),
            style: MenuItemButton.styleFrom(
              minimumSize: const Size(200, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              foregroundColor: AppColors.body,
            ),
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) {
        return Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: const SizedBox(
              width: 28,
              height: 28,
              child: Tooltip(
                message: 'Add element',
                child: Icon(Icons.add_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }
}
