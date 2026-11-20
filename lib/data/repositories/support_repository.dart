import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';
import '../../features/auth/auth_state.dart';
import '../models/support_ticket.dart';

abstract interface class SupportRepository {
  Future<bool> isAdmin();
  Future<List<SupportTicket>> loadTickets();
  Future<SupportDetail?> loadDetail(String id);
  Future<String> create({
    required String id,
    required String category,
    required String description,
    Uint8List? photo,
  });
  Future<void> update(SupportTicket ticket, String status, String message);
}

String newSupportId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class SupabaseSupportRepository implements SupportRepository {
  final SupabaseClient client;
  const SupabaseSupportRepository(this.client);
  @override
  Future<bool> isAdmin() async => await client.rpc('is_support_admin') == true;

  @override
  Future<List<SupportTicket>> loadTickets() async {
    final tickets = <SupportTicket>[];
    for (var offset = 0; ; offset += 500) {
      final rows = await client
          .from('support_tickets')
          .select()
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 499);
      tickets.addAll(rows.map(SupportTicket.fromMap));
      if (rows.length < 500) return tickets;
    }
  }

  @override
  Future<SupportDetail?> loadDetail(String id) async {
    final row = await client
        .from('support_tickets')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final ticket = SupportTicket.fromMap(row);
    final rows = await client
        .from('support_ticket_events')
        .select()
        .eq('ticket_id', id)
        .order('id');
    String? url;
    if (ticket.photoPath != null) {
      try {
        url = await client.storage
            .from('support-attachments')
            .createSignedUrl(ticket.photoPath!, 300);
      } on StorageException {
        // A missing attachment must not hide the report or its processing history.
      }
    }
    return SupportDetail(ticket, rows.map(SupportEvent.fromMap).toList(), url);
  }

  @override
  Future<String> create({
    required String id,
    required String category,
    required String description,
    Uint8List? photo,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Silakan login kembali.');
    String? path;
    if (photo != null) {
      if (photo.isEmpty || photo.length > 5 * 1024 * 1024) {
        throw StateError('Foto maksimal 5 MB.');
      }
      final type = supportPhotoType(photo);
      path = '$uid/$id/photo.${type.$1}';
      try {
        await client.storage
            .from('support-attachments')
            .uploadBinary(
              path,
              photo,
              fileOptions: FileOptions(contentType: type.$2, upsert: false),
            );
      } on StorageException catch (error) {
        // Retry the same immutable upload after a lost response.
        if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
      }
    }
    return await client.rpc(
      'create_support_ticket',
      params: {
        'p_id': id,
        'p_category': category,
        'p_description': description,
        'p_photo_path': path,
      },
    ) as String;
  }

  @override
  Future<void> update(
    SupportTicket ticket,
    String status,
    String message,
  ) async {
    await client.rpc(
      'update_support_ticket',
      params: {
        'p_id': ticket.id,
        'p_expected_version': ticket.version,
        'p_status': status,
        'p_message': message,
      },
    );
  }
}

(String, String) supportPhotoType(Uint8List data) {
  if (data.length >= 3 && data[0] == 255 && data[1] == 216 && data[2] == 255) {
    return ('jpg', 'image/jpeg');
  }
  if (data.length >= 8 &&
      data[0] == 137 &&
      data[1] == 80 &&
      data[2] == 78 &&
      data[3] == 71) {
    return ('png', 'image/png');
  }
  if (data.length >= 12 &&
      String.fromCharCodes(data.take(4)) == 'RIFF' &&
      String.fromCharCodes(data.skip(8).take(4)) == 'WEBP') {
    return ('webp', 'image/webp');
  }
  throw StateError('Gunakan foto JPG, PNG, atau WebP.');
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  if (!ref.watch(supabaseRuntimeConfigProvider).isConfigured) {
    throw StateError('Hubungkan Supabase untuk mengirim laporan.');
  }
  return SupabaseSupportRepository(Supabase.instance.client);
});
final supportAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || !ref.watch(supabaseRuntimeConfigProvider).isConfigured) {
    return false;
  }
  return ref.watch(supportRepositoryProvider).isAdmin();
});
final supportTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((
  ref,
) async {
  if (ref.watch(authNotifierProvider).user == null) return [];
  final timer = Timer(const Duration(seconds: 10), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(supportRepositoryProvider).loadTickets();
});
final supportDetailProvider = FutureProvider.autoDispose
    .family<SupportDetail?, String>((ref, id) async {
      if (ref.watch(authNotifierProvider).user == null) return null;
      final timer = Timer(const Duration(seconds: 10), ref.invalidateSelf);
      ref.onDispose(timer.cancel);
      return ref.watch(supportRepositoryProvider).loadDetail(id);
    });

String supportError(Object error) {
  if (error is PostgrestException &&
      const ['42501', '40001', '22023'].contains(error.code)) {
    return error.message;
  }
  if (error is StateError) return error.message;
  return 'Belum berhasil terhubung ke server. Periksa koneksi lalu coba lagi.';
}
