import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Profile photos in `avatars/{uid}` as Base64 JPEG. Separate from `users/{uid}`, so
/// the admin user list never downloads every photo. Rules: owner writes, owner and staff read.
abstract interface class AvatarRepository {
  /// The photo, or null when there is none or it cannot be read.
  Future<Uint8List?> load(String uid);

  /// Saves a JPEG of at most [avatarMaxBytes].
  Future<void> save(String uid, Uint8List jpeg);

  Future<void> remove(String uid);
}

/// Must stay below the 40,000 Base64 characters allowed in firestore.rules
/// (29 KB is 39,596 characters once encoded).
const int avatarMaxBytes = 29 * 1024;

class FirestoreAvatarRepository implements AvatarRepository {
  FirestoreAvatarRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.collection('avatars').doc(uid);

  @override
  Future<Uint8List?> load(String uid) async {
    final encoded = (await _doc(uid).get()).data()?['imageBase64'];
    if (encoded is! String) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String uid, Uint8List jpeg) {
    if (jpeg.isEmpty || jpeg.length > avatarMaxBytes) throw ArgumentError.value(jpeg.length, 'jpeg');
    return _doc(uid).set({'imageBase64': base64Encode(jpeg), 'updatedAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> remove(String uid) => _doc(uid).delete();
}
