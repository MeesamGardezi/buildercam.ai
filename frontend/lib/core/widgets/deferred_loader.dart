// Purpose: Generic loader for Dart deferred (lazy-loaded) libraries.
//
// Wraps `loadLibrary()` of a `deferred as` import so heavy code is fetched
// on demand (off the initial web bundle) and a placeholder/error UI is shown
// while it downloads. Once a deferred library is loaded, subsequent calls to
// `loadLibrary()` resolve synchronously, so reopening the screen is instant.
import 'package:flutter/material.dart';

/// Loads a deferred library via [loadLibrary] and builds [builder] once ready.
///
/// ```dart
/// import 'package:.../pdf_editor_widget.dart' deferred as pdf_editor;
///
/// DeferredLoader(
///   loadLibrary: pdf_editor.loadLibrary,
///   builder: (context) => pdf_editor.PdfEditorWidget(...),
/// )
/// ```
class DeferredLoader extends StatefulWidget {
  const DeferredLoader({
    super.key,
    required this.loadLibrary,
    required this.builder,
    this.placeholder,
    this.errorBuilder,
  });

  /// The `loadLibrary` tear-off of a `deferred as` import.
  final Future<void> Function() loadLibrary;

  /// Builds the deferred content once the library has loaded.
  final WidgetBuilder builder;

  /// Shown while the library is downloading. Defaults to a centered spinner.
  final Widget? placeholder;

  /// Shown if loading fails. Defaults to a centered error message with retry.
  final Widget Function(BuildContext context, Object error, VoidCallback retry)?
      errorBuilder;

  @override
  State<DeferredLoader> createState() => _DeferredLoaderState();
}

class _DeferredLoaderState extends State<DeferredLoader> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadLibrary();
  }

  void _retry() {
    setState(() {
      _future = widget.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            if (widget.errorBuilder != null) {
              return widget.errorBuilder!(context, snapshot.error!, _retry);
            }
            return _DefaultError(error: snapshot.error!, onRetry: _retry);
          }
          return widget.builder(context);
        }
        return widget.placeholder ??
            const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class _DefaultError extends StatelessWidget {
  const _DefaultError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40),
          const SizedBox(height: 12),
          const Text('Failed to load this section.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
