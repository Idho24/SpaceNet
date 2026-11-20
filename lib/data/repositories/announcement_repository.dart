import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';
import '../../features/auth/auth_state.dart';

const announcementKinds = {
  'maintenance': 'Perbaikan / pemeliharaan',
  'outage': 'Gangguan massal',
};
const announcementStatuses = {
  'scheduled': 'Terjadwal',
  'in_progress': 'Dalam penanganan',
  'resolved': 'Selesai',
};

class ServiceAnnouncement {
  final String id, kind, title, message, area, status;
  final int version;
  final bool archived, unread;
  final DateTime updatedAt;
  const ServiceAnnouncement({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.area,
    required this.status,
    required this.version,
    required this.archived,
    required this.unread,
    required this.updatedAt,
  });
  factory ServiceAnnouncement.fromMap(
    Map<String, dynamic> row,
    int readVersion,
  ) => ServiceAnnouncement(
    id: row['id'] as String,
    kind: row['kind'] as String,
    title: row['title'] as String,
    message: row['message'] as String,
    area: row['area'] as String,
    status: row['status'] as String,
    version: (row['version'] as num).toInt(),
    archived: row['archived'] as bool,
    unread: readVersion < (row['version'] as num).toInt(),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}

abstract interface class AnnouncementRepository {
  Future<List<ServiceAnnouncement>> load();
  Future<void> save({
    required String id,
    required int version,
    required String kind,
    required String title,
    required String message,
    required String area,
    required String status,
    required bool archived,
  });
  Future<void> markRead(ServiceAnnouncement item);
  Future<bool> preference();
  Future<void> setPreference(bool enabled);
}

class SupabaseAnnouncementRepository implements AnnouncementRepository {
  final SupabaseClient client;
  const SupabaseAnnouncementRepository(this.client);
  @override
  Future<List<ServiceAnnouncement>> load() async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('service_announcements')
          .select()
          .order('updated_at', ascending: false)
          .order('id')
          .range(offset, offset + 499);
      rows.addAll(page);
      if (page.length < 500) break;
    }
    final reads = <String, int>{};
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('service_announcement_reads')
          .select('announcement_id,version')
          .order('announcement_id')
          .range(offset, offset + 499);
      for (final row in page) {
        reads[row['announcement_id'] as String] = (row['version'] as num)
            .toInt();
      }
      if (page.length < 500) break;
    }
    return rows
        .map((row) => ServiceAnnouncement.fromMap(row, reads[row['id']] ?? 0))
        .toList();
  }

  @override
  Future<void> save({
    required String id,
    required int version,
    required String kind,
    required String title,
    required String message,
    required String area,
    required String status,
    required bool archived,
  }) async {
    await client.rpc(
      'save_service_announcement',
      params: {
        'p_id': id,
        'p_version': version,
        'p_kind': kind,
        'p_title': title,
        'p_message': message,
        'p_area': area,
        'p_status': status,
        'p_archived': archived,
      },
    );
  }

  @override
  Future<void> markRead(ServiceAnnouncement item) async {
    await client.rpc(
      'read_service_announcement',
      params: {'p_id': item.id, 'p_version': item.version},
    );
  }

  @override
  Future<bool> preference() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return true;
    final row = await client
        .from('notification_preferences')
        .select('service_enabled')
        .eq('user_id', uid)
        .maybeSingle();
    return row?['service_enabled'] as bool? ?? true;
  }

  @override
  Future<void> setPreference(bool enabled) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Silakan login kembali.');
    await client.from('notification_preferences').upsert({
      'user_id': uid,
      'service_enabled': enabled,
    });
  }
}

final announcementRepositoryProvider = Provider<AnnouncementRepository>(
  (ref) => SupabaseAnnouncementRepository(Supabase.instance.client),
);
final announcementsProvider =
    FutureProvider.autoDispose<List<ServiceAnnouncement>>((ref) async {
      final user = ref.watch(authNotifierProvider).user;
      if (user == null ||
          !ref.watch(supabaseRuntimeConfigProvider).isConfigured) {
        return [];
      }
      final repo = ref.watch(announcementRepositoryProvider);
      Timer? timer;
      var disposed = false;
      ref.onDispose(() {
        disposed = true;
        timer?.cancel();
      });
      try {
        return await repo.load();
      } finally {
        if (!disposed) {
          timer = Timer(const Duration(seconds: 10), ref.invalidateSelf);
        }
      }
    });
final servicePreferenceProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(authNotifierProvider).user == null ||
      !ref.watch(supabaseRuntimeConfigProvider).isConfigured) {
    return true;
  }
  return ref.watch(announcementRepositoryProvider).preference();
});

// Finish saving and refresh the shared preference even if the settings page closes.
final saveServicePreferenceProvider = Provider<Future<void> Function(bool)>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return (enabled) async {
    await ref.read(announcementRepositoryProvider).setPreference(enabled);
    if (!disposed) ref.invalidate(servicePreferenceProvider);
  };
});
