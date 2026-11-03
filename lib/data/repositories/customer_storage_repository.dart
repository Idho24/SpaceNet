import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

abstract interface class CustomerStorageRepository {
  Future<String> uploadTicketPhoto({
    required String ticketId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  });
}

class FirebaseCustomerStorageRepository implements CustomerStorageRepository {
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  FirebaseCustomerStorageRepository({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<String> uploadTicketPhoto({
    required String ticketId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Login diperlukan untuk mengunggah foto.');
    }
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException(
        'Ukuran foto harus lebih dari 0 dan maksimal 5 MB.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(ticketId)) {
      throw const FormatException('ID tiket tidak valid.');
    }
    const allowedTypes = {'image/jpeg', 'image/png', 'image/webp'};
    if (!allowedTypes.contains(contentType)) {
      throw const FormatException('Format foto harus JPEG, PNG, atau WebP.');
    }
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final safeName = DateTime.now().microsecondsSinceEpoch;
    final reference = _storage.ref().child(
      'ticket-attachments/${user.uid}/$ticketId/$safeName.$extension',
    );
    final result = await reference.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {'source': 'customer'},
      ),
    );
    return result.ref.getDownloadURL();
  }
}
