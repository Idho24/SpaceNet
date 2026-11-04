import 'dart:typed_data';

abstract interface class CustomerStorageRepository {
  Future<String> uploadTicketPhoto({
    required String ticketId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  });
}

class MockCustomerStorageRepository implements CustomerStorageRepository {
  @override
  Future<String> uploadTicketPhoto({
    required String ticketId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
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

    return 'https://storage.local.example/$ticketId/$fileName';
  }
}
