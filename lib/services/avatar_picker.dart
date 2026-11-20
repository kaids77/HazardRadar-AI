import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'avatar_repository.dart';
import 'photo_service.dart';

enum AvatarSource { camera, gallery }

abstract interface class AvatarPicker {
  /// A small square-ish JPEG of at most [avatarMaxBytes], or null when the user cancels.
  /// Throws [PhotoTooLargeException] when the picture cannot be made small enough.
  Future<Uint8List?> pick(AvatarSource source);
}

class ImageAvatarPicker implements AvatarPicker {
  ImageAvatarPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Big enough for the 64 px Settings photo on a 3x screen.
  static const int _side = 256;

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(AvatarSource source) async {
    final shot = await _picker.pickImage(
      source: source == AvatarSource.camera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: _side.toDouble(),
      maxHeight: _side.toDouble(),
    );
    if (shot == null) return null;
    final original = await shot.readAsBytes();
    // compressWithList works on Android, iOS, and web (compressWithFile does not on web).
    return compressToLimit(
      (quality) => FlutterImageCompress.compressWithList(
        original,
        quality: quality,
        minWidth: _side,
        minHeight: _side,
        format: CompressFormat.jpeg,
      ),
      maxBytes: avatarMaxBytes,
    );
  }
}
