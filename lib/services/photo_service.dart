import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../models/report.dart';

class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException();

  @override
  String toString() => 'The photo could not be compressed below 150 KB.';
}

abstract interface class PhotoCapture {
  /// Opens the camera. Returns null if the user cancels.
  /// Throws [PhotoTooLargeException] if the photo cannot be made small enough.
  Future<CompressedPhoto?> takePhoto();
}

/// Tries each quality in turn and returns the first result within [maxBytes].
/// Kept separate from the camera and native codec so it can be tested alone.
Future<Uint8List> compressToLimit(
  Future<Uint8List> Function(int quality) encode, {
  int maxBytes = CompressedPhoto.maxBytes,
  List<int> qualities = const [80, 65, 50, 35, 25],
}) async {
  for (final quality in qualities) {
    final bytes = await encode(quality);
    if (bytes.isNotEmpty && bytes.length <= maxBytes) return bytes;
  }
  throw const PhotoTooLargeException();
}

class CameraPhotoCapture implements PhotoCapture {
  CameraPhotoCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const int _maxSide = 1080;

  final ImagePicker _picker;

  @override
  Future<CompressedPhoto?> takePhoto() async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxSide.toDouble(),
      maxHeight: _maxSide.toDouble(),
    );
    if (shot == null) return null;

    // compressWithList works on Android, iOS and web. compressWithFile is not
    // implemented on web and throws there.
    final original = await shot.readAsBytes();
    final bytes = await compressToLimit(
      (quality) => FlutterImageCompress.compressWithList(
        original,
        quality: quality,
        minWidth: _maxSide,
        minHeight: _maxSide,
        format: CompressFormat.jpeg,
      ),
    );
    return CompressedPhoto(bytes: bytes);
  }
}
