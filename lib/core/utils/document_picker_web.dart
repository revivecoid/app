import 'dart:async';
import 'dart:js_interop';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

/// Web document picking: an `<input type="file">` with an accept list that
/// covers PDFs as well as images.
///
/// Mirrors the approach `image_picker_for_web` uses internally — append a
/// detached input to the DOM, click it, wait for `change`, then remove it.
/// `cancel` is handled so that dismissing the dialog completes with `null`
/// instead of leaving the future pending (the browsers that raise it also fire
/// `change` when a file *is* chosen, so this cannot swallow a selection).
Future<XFile?> pickDocument({required String accept}) {
  final completer = Completer<XFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..accept = accept;

  // Visually hidden but still clickable — `display: none` blocks .click() in
  // some browsers.
  input.style
    ..position = 'fixed'
    ..left = '-10000px'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0';

  input.onchange = (web.Event _) {
    final files = input.files;
    if (completer.isCompleted) return;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    completer.complete(XFile(
      web.URL.createObjectURL(file),
      name: file.name,
      length: file.size,
      lastModified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
      mimeType: file.type,
    ));
  }.toJS;

  input.oncancel = (web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }.toJS;

  web.document.body!.appendChild(input);
  input.click();

  return completer.future.whenComplete(() => input.remove());
}
