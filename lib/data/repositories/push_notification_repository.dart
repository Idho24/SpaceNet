import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthorizationStatus { notDetermined, granted, denied }

class NotificationSettings {
  final AuthorizationStatus authorizationStatus;

  const NotificationSettings(this.authorizationStatus);
}

class PushNotificationRepository {
  Stream<String> get foregroundMessages => const Stream.empty();

  Future<NotificationSettings> requestPermission() async {
    return const NotificationSettings(AuthorizationStatus.granted);
  }

  Future<String> registerDevice() async {
    return 'demo-device-token';
  }
}

final pushNotificationRepositoryProvider =
    Provider<PushNotificationRepository?>((ref) {
      return PushNotificationRepository();
    });
