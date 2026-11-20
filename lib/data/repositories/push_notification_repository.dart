import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Android renders visible FCM payloads even when no Dart isolate is running.
class PushNotificationRepository {
  static final instance = PushNotificationRepository();
  bool available = false;
  bool openInboxOnStart = false;
  String? _token;
  String? _registeredUser;
  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!isAndroid) return;
    try {
      await Firebase.initializeApp();
      available = true;
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      openInboxOnStart = initial?.data['type'] == 'service_announcement';
    } catch (_) {
      available = false;
    }
  }

  Stream<String> get tokenChanges => available
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream.empty();
  Stream<RemoteMessage> get openedMessages =>
      available ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();
  Stream<RemoteMessage> get foregroundMessages =>
      available ? FirebaseMessaging.onMessage : const Stream.empty();

  Future<bool> permissionGranted() async {
    if (!available) return false;
    final result = await FirebaseMessaging.instance.getNotificationSettings();
    return result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> requestPermission() async {
    if (!available)
      throw StateError('Konfigurasi Firebase belum tersedia pada APK ini.');
    final result = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> registerDevice(String uid, {String? refreshedToken}) async {
    if (!available || !await permissionGranted()) return false;
    final client = Supabase.instance.client;
    if (client.auth.currentUser?.id != uid)
      throw StateError(
        'Masuk dengan akun pelanggan untuk mengaktifkan notifikasi HP.',
      );
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    final token = refreshedToken ?? await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty)
      throw StateError(
        'Token notifikasi belum tersedia. Coba lagi saat koneksi stabil.',
      );
    if (client.auth.currentUser?.id != uid) return false;
    await client.rpc('register_push_device', params: {'p_token': token});
    _token = token;
    _registeredUser = uid;
    return true;
  }

  Future<bool> serverEnabled() async =>
      await Supabase.instance.client.rpc('service_push_enabled') == true;

  Future<void> unregisterBeforeLogout() async {
    if (!available) return;
    try {
      final token = _token ?? await FirebaseMessaging.instance.getToken();
      if (token != null &&
          (_registeredUser == null ||
              _registeredUser ==
                  Supabase.instance.client.auth.currentUser?.id)) {
        await Supabase.instance.client.rpc(
          'unregister_push_device',
          params: {'p_token': token},
        );
      }
    } catch (_) {
      // Session removal on the server also removes its registered devices.
    } finally {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
      } catch (_) {}
      _token = null;
      _registeredUser = null;
    }
  }
}

final pushNotificationRepositoryProvider = Provider<PushNotificationRepository>(
  (ref) => PushNotificationRepository.instance,
);
final pushInboxRequestedProvider = StateProvider<bool>(
  (ref) => PushNotificationRepository.instance.openInboxOnStart,
);
