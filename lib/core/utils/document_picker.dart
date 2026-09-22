import 'package:image_picker/image_picker.dart';

import 'document_picker_stub.dart'
    if (dart.library.js_interop) 'document_picker_web.dart' as impl;

/// Picks a partner document — PDF or image — from the device.
///
/// [ImagePicker] cannot do this on web: the file input it injects is hard-coded
/// to `accept="image/*"`, so the browser filters PDFs out of the dialog and no
/// error is ever raised — the file simply cannot be chosen. The web
/// implementation therefore drives its own `<input type="file">` with a wider
/// accept list.
class DocumentPicker {
  const DocumentPicker._();

  /// MIME types offered in the file dialog.
  static const String acceptTypes = 'application/pdf,image/*';

  /// Upper bound advertised on the upload rows ("PDF, JPG up to 10MB").
  static const int maxBytes = 10 * 1024 * 1024;

  /// Opens the picker and returns the chosen file, or `null` if the user
  /// cancelled or picked nothing.
  static Future<XFile?> pick({String accept = acceptTypes}) =>
      impl.pickDocument(accept: accept);
}
