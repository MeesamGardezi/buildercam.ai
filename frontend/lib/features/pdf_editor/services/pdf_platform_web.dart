// ignore_for_file: deprecated_member_use

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Creates a temporary blob URL and clicks a hidden anchor to trigger
/// a browser file-save dialog.
void triggerWebDownload({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

/// Opens a blank tab synchronously while the user gesture is still active.
/// Later, [openWebBlob] navigates it to the generated PDF and invokes print.
Object? prepareWebPrintTarget() {
  try {
    return html.window.open('about:blank', '_blank');
  } catch (_) {
    return null;
  }
}

/// Loads the PDF into an off-screen iframe and asks the browser to open the
/// print dialog immediately. If the browser blocks iframe printing, falls back
/// to a normal PDF tab.
void openWebBlob({
  required Uint8List bytes,
  required String mimeType,
  Object? printTarget,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  if (printTarget != null && _printViaPreparedWindow(printTarget, url)) {
    return;
  }

  final iframe = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.opacity = '0'
    ..style.border = '0';

  var usedFallback = false;
  void fallback() {
    if (usedFallback) return;
    usedFallback = true;
    html.window.open(url, '_blank');
  }

  html.document.body?.append(iframe);
  iframe.onLoad.first.then((_) {
    try {
      final contentWindow = iframe.contentWindow;
      if (contentWindow == null) {
        fallback();
        return;
      }
      (contentWindow as html.Window).print();
    } catch (_) {
      fallback();
    }
  }).catchError((_) {
    fallback();
  });

  // Delay cleanup so the browser PDF viewer has time to load and print.
  Future.delayed(const Duration(seconds: 45), () {
    iframe.remove();
    html.Url.revokeObjectUrl(url);
  });
}

bool _printViaPreparedWindow(Object printTarget, String url) {
  final targetWindow = printTarget is html.Window ? printTarget : null;
  if (targetWindow == null) {
    return false;
  }

  var cleanedUp = false;

  void cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    html.Url.revokeObjectUrl(url);
  }

  var usedFallback = false;
  void fallback() {
    if (usedFallback) return;
    usedFallback = true;
    try {
      targetWindow.location.assign(url);
    } catch (_) {
      html.window.open(url, '_blank');
    }
  }

  final doc = targetWindow.document;
  if (doc is! html.HtmlDocument) {
    try {
      targetWindow.close();
    } catch (_) {}
    return false;
  }

  final body = doc.body;
  if (body == null) {
    try {
      targetWindow.close();
    } catch (_) {}
    return false;
  }

  try {
    // Build a same-origin print shell so we can print once the PDF iframe loads.
    body.children.clear();
    body.style.margin = '0';
    body.style.overflow = 'hidden';

    final loading = html.DivElement()
      ..text = 'Preparing print preview...'
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.right = '0'
      ..style.bottom = '0'
      ..style.left = '0'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'center'
      ..style.fontFamily = 'sans-serif'
      ..style.fontSize = '14px'
      ..style.color = '#6b7280'
      ..style.backgroundColor = '#ffffff';
    body.append(loading);

    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'fixed'
      ..style.left = '0'
      ..style.top = '0';
    body.append(iframe);

    iframe.onLoad.first.then((_) {
      try {
        loading.remove();
        final contentWindow = iframe.contentWindow;
        if (contentWindow == null) {
          fallback();
          return;
        }
        (contentWindow as html.Window).print();
      } catch (_) {
        fallback();
      }
    }).catchError((_) {
      fallback();
    });

    // If the iframe never loads, fall back to a plain PDF tab.
    Future.delayed(const Duration(seconds: 8), () {
      if (usedFallback) return;
      if (iframe.contentWindow == null) {
        fallback();
      }
    });

    Future.delayed(const Duration(seconds: 90), cleanup);
  } catch (_) {
    fallback();
    Future.delayed(const Duration(seconds: 90), cleanup);
  }

  return true;
}
