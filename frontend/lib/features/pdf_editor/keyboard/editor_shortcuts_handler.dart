import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/template_editor_provider.dart';

// ── Intent declarations ──────────────────────────────────────────────────────

class UndoIntent extends Intent { const UndoIntent(); }
class RedoIntent extends Intent { const RedoIntent(); }
class CopyIntent extends Intent { const CopyIntent(); }
class CutIntent extends Intent { const CutIntent(); }
class PasteIntent extends Intent { const PasteIntent(); }
class DuplicateIntent extends Intent { const DuplicateIntent(); }
class SelectAllIntent extends Intent { const SelectAllIntent(); }
class DeleteElementIntent extends Intent { const DeleteElementIntent(); }
class DeselectIntent extends Intent { const DeselectIntent(); }
class BringForwardIntent extends Intent { const BringForwardIntent(); }
class SendBackwardIntent extends Intent { const SendBackwardIntent(); }
class BringToFrontIntent extends Intent { const BringToFrontIntent(); }
class SendToBackIntent extends Intent { const SendToBackIntent(); }

class NudgeIntent extends Intent {
  final double dx;
  final double dy;
  const NudgeIntent(this.dx, this.dy);
}

class ZoomInIntent extends Intent { const ZoomInIntent(); }
class ZoomOutIntent extends Intent { const ZoomOutIntent(); }
class ZoomResetIntent extends Intent { const ZoomResetIntent(); }
class SaveIntent extends Intent { const SaveIntent(); }

// ── Shortcut map ─────────────────────────────────────────────────────────────

// Register both Ctrl and Meta (Cmd) variants so shortcuts work on every
// platform and browser (macOS web sends Meta, Windows/Linux send Ctrl).
Map<ShortcutActivator, Intent> buildShortcuts() => {
      // Undo
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): const UndoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):    const UndoIntent(),

      // Redo (Shift+Z or Y)
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): const RedoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true,    shift: true): const RedoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): const RedoIntent(),
      const SingleActivator(LogicalKeyboardKey.keyY, meta: true):    const RedoIntent(),

      // Clipboard
      const SingleActivator(LogicalKeyboardKey.keyC, control: true): const CopyIntent(),
      const SingleActivator(LogicalKeyboardKey.keyC, meta: true):    const CopyIntent(),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true): const CutIntent(),
      const SingleActivator(LogicalKeyboardKey.keyX, meta: true):    const CutIntent(),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true): const PasteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyV, meta: true):    const PasteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): const DuplicateIntent(),
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true):    const DuplicateIntent(),

      // Selection
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): const SelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true):    const SelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): const DeselectIntent(),

      // Delete
      const SingleActivator(LogicalKeyboardKey.delete):    const DeleteElementIntent(),
      const SingleActivator(LogicalKeyboardKey.backspace): const DeleteElementIntent(),

      // Z-order
      const SingleActivator(LogicalKeyboardKey.bracketRight, control: true): const BringForwardIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):    const BringForwardIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketLeft,  control: true): const SendBackwardIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketLeft,  meta: true):    const SendBackwardIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketRight, control: true, shift: true): const BringToFrontIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true,    shift: true): const BringToFrontIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketLeft,  control: true, shift: true): const SendToBackIntent(),
      const SingleActivator(LogicalKeyboardKey.bracketLeft,  meta: true,    shift: true): const SendToBackIntent(),

      // Nudge 1 unit
      const SingleActivator(LogicalKeyboardKey.arrowLeft):  const NudgeIntent(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): const NudgeIntent(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp):    const NudgeIntent(0, -1),
      const SingleActivator(LogicalKeyboardKey.arrowDown):  const NudgeIntent(0, 1),

      // Nudge 10 units (Shift+Arrow)
      const SingleActivator(LogicalKeyboardKey.arrowLeft,  shift: true): const NudgeIntent(-10, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): const NudgeIntent(10, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp,    shift: true): const NudgeIntent(0, -10),
      const SingleActivator(LogicalKeyboardKey.arrowDown,  shift: true): const NudgeIntent(0, 10),

      // Zoom
      const SingleActivator(LogicalKeyboardKey.equal, control: true): const ZoomInIntent(),
      const SingleActivator(LogicalKeyboardKey.equal, meta: true):    const ZoomInIntent(),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): const ZoomOutIntent(),
      const SingleActivator(LogicalKeyboardKey.minus, meta: true):    const ZoomOutIntent(),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): const ZoomResetIntent(),
      const SingleActivator(LogicalKeyboardKey.digit0, meta: true):    const ZoomResetIntent(),

      // Save
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): const SaveIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true):    const SaveIntent(),
    };

// ── Action builder ───────────────────────────────────────────────────────────

Map<Type, Action<Intent>> buildActions({
  required TemplateEditorProvider provider,
  required VoidCallback onSave,
}) =>
    {
      UndoIntent: CallbackAction<UndoIntent>(
        onInvoke: (_) { provider.undo(); return null; },
      ),
      RedoIntent: CallbackAction<RedoIntent>(
        onInvoke: (_) { provider.redo(); return null; },
      ),
      CopyIntent: CallbackAction<CopyIntent>(
        onInvoke: (_) { provider.copySelected(); return null; },
      ),
      CutIntent: CallbackAction<CutIntent>(
        onInvoke: (_) { provider.cutSelected(); return null; },
      ),
      PasteIntent: CallbackAction<PasteIntent>(
        onInvoke: (_) { provider.paste(); return null; },
      ),
      DuplicateIntent: CallbackAction<DuplicateIntent>(
        onInvoke: (_) { provider.duplicateSelected(); return null; },
      ),
      SelectAllIntent: CallbackAction<SelectAllIntent>(
        onInvoke: (_) { provider.selectAll(); return null; },
      ),
      DeleteElementIntent: CallbackAction<DeleteElementIntent>(
        onInvoke: (_) {
          // Guard: do not delete while the user is typing inside a text field.
          if (!provider.isEditingText) provider.deleteSelected();
          return null;
        },
      ),
      DeselectIntent: CallbackAction<DeselectIntent>(
        onInvoke: (_) {
          if (provider.isEditingText) {
            provider.exitTextEdit();
          } else {
            provider.deselectAll();
          }
          return null;
        },
      ),
      BringForwardIntent: CallbackAction<BringForwardIntent>(
        onInvoke: (_) {
          final id = provider.primarySelected?.id;
          if (id != null) provider.bringForward(id);
          return null;
        },
      ),
      SendBackwardIntent: CallbackAction<SendBackwardIntent>(
        onInvoke: (_) {
          final id = provider.primarySelected?.id;
          if (id != null) provider.sendBackward(id);
          return null;
        },
      ),
      BringToFrontIntent: CallbackAction<BringToFrontIntent>(
        onInvoke: (_) {
          final id = provider.primarySelected?.id;
          if (id != null) provider.bringToFront(id);
          return null;
        },
      ),
      SendToBackIntent: CallbackAction<SendToBackIntent>(
        onInvoke: (_) {
          final id = provider.primarySelected?.id;
          if (id != null) provider.sendToBack(id);
          return null;
        },
      ),
      NudgeIntent: CallbackAction<NudgeIntent>(
        onInvoke: (intent) {
          if (!provider.isEditingText) provider.nudge(intent.dx, intent.dy);
          return null;
        },
      ),
      ZoomInIntent: CallbackAction<ZoomInIntent>(
        onInvoke: (_) { provider.setZoom(provider.zoom + 0.1); return null; },
      ),
      ZoomOutIntent: CallbackAction<ZoomOutIntent>(
        onInvoke: (_) { provider.setZoom(provider.zoom - 0.1); return null; },
      ),
      ZoomResetIntent: CallbackAction<ZoomResetIntent>(
        onInvoke: (_) { provider.resetZoom(); return null; },
      ),
      SaveIntent: CallbackAction<SaveIntent>(
        onInvoke: (_) { onSave(); return null; },
      ),
    };

// ── Convenience wrapper widget ────────────────────────────────────────────────

/// Wraps the editor scaffold with Shortcuts + Actions.
/// All keyboard logic lives here — nothing keyboard-related is in widget files.
class EditorShortcutsWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onSave;

  const EditorShortcutsWrapper({
    super.key,
    required this.child,
    required this.onSave,
  });

  @override
  State<EditorShortcutsWrapper> createState() => _EditorShortcutsWrapperState();
}

class _EditorShortcutsWrapperState extends State<EditorShortcutsWrapper> {
  bool _hasEditableFocus = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
    _hasEditableFocus = _isEditableTextFocused();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    final next = _isEditableTextFocused();
    if (next == _hasEditableFocus) return;
    setState(() => _hasEditableFocus = next);
  }

  bool _isEditableTextFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TemplateEditorProvider>();
    return Shortcuts(
      shortcuts: _hasEditableFocus ? const {} : buildShortcuts(),
      child: Actions(
        actions: buildActions(provider: provider, onSave: widget.onSave),
        child: Focus(
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}
