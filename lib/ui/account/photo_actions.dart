import 'package:flutter/material.dart';

import '../../services/avatar_picker.dart';

/// What the user chose for their profile photo.
sealed class PhotoAction {
  const PhotoAction();
}

class PickPhoto extends PhotoAction {
  const PickPhoto(this.source);

  final AvatarSource source;
}

class RemovePhoto extends PhotoAction {
  const RemovePhoto();
}

/// A flat bottom sheet: take a photo, choose one, or remove the current one.
/// Resolves to null when closed.
Future<PhotoAction?> askPhotoAction(BuildContext context, {required bool hasPhoto}) {
  return showModalBottomSheet<PhotoAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('Profile photo', style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(context).pop(const PickPhoto(AvatarSource.camera)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(context).pop(const PickPhoto(AvatarSource.gallery)),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () => Navigator.of(context).pop(const RemovePhoto()),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
