import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_runtime_config.dart';

class PushNotificationRepository {
  final FirebaseMessaging _messaging;

  PushNotificationRepository({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  Future<NotificationSettings> requestPermission() {
    return _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<String> registerDevice() async {
    const vapidKey = String.fromEnvironment('FIREBASE_MESSAGING_VAPID_KEY');
    if (kIsWeb && vapidKey.isEmpty) {
      throw StateError(
        'FIREBASE_MESSAGING_VAPID_KEY wajib diatur untuk notifikasi Web.',
      );
    }
    final registeredFid = Completer<String>();
    final subscription = _messaging.onRegistered.listen(
      (fid) {
        if (!registeredFid.isCompleted) registeredFid.complete(fid);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!registeredFid.isCompleted) {
          registeredFid.completeError(error, stackTrace);
        }
      },
    );
    try {
      await _messaging.register(
        vapidKey: kIsWeb && vapidKey.isNotEmpty ? vapidKey : null,
      );
      return await registeredFid.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
    }
  }
}

final pushNotificationRepositoryProvider =
    Provider<PushNotificationRepository?>((ref) {
      if (!ref.watch(firebaseRuntimeConfigProvider).isConfigured) return null;
      return PushNotificationRepository();
    });
