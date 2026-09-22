import 'package:image_picker/image_picker.dart';

/// Native (Android/iOS/desktop) document picking.
///
/// There is no `accept` filter to work around here, so this keeps the previous
/// gallery behaviour. Note that `image_picker` can only return images on these
/// platforms — reaching PDFs on native needs a file-picker plugin.
Future<XFile?> pickDocument({required String accept}) =>
    ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
