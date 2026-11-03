import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirebaseRuntimeConfig {
  final String projectId;
  final String apiKey;
  final String messagingSenderId;
  final String authDomain;
  final String storageBucket;
  final String androidAppId;
  final String iosAppId;
  final String webAppId;
  final String iosBundleId;
  final String measurementId;
  final String googleWebClientId;
  final String appCheckWebSiteKey;
  final bool useEmulators;
  final bool enableAppCheck;
  final String? emulatorHostOverride;

  const FirebaseRuntimeConfig({
    required this.projectId,
    required this.apiKey,
    required this.messagingSenderId,
    required this.authDomain,
    required this.storageBucket,
    required this.androidAppId,
    required this.iosAppId,
    required this.webAppId,
    required this.iosBundleId,
    required this.measurementId,
    required this.googleWebClientId,
    required this.appCheckWebSiteKey,
    required this.useEmulators,
    required this.enableAppCheck,
    required this.emulatorHostOverride,
  });

  factory FirebaseRuntimeConfig.fromEnvironment() {
    return const FirebaseRuntimeConfig(
      projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
      apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
      messagingSenderId: String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
      iosAppId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
      webAppId: String.fromEnvironment('FIREBASE_WEB_APP_ID'),
      iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
      measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
      googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      appCheckWebSiteKey: String.fromEnvironment(
        'FIREBASE_APP_CHECK_WEB_SITE_KEY',
      ),
      useEmulators: bool.fromEnvironment('FIREBASE_USE_EMULATORS'),
      enableAppCheck: bool.fromEnvironment('FIREBASE_ENABLE_APP_CHECK'),
      emulatorHostOverride: String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: '',
      ),
    );
  }

  bool get isConfigured {
    final platformAppId = switch (defaultTargetPlatform) {
      TargetPlatform.android => androidAppId,
      TargetPlatform.iOS => iosAppId,
      _ => kIsWeb ? webAppId : '',
    };
    return projectId.isNotEmpty &&
        apiKey.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        platformAppId.isNotEmpty;
  }

  FirebaseOptions get firebaseOptions {
    final appId = switch (defaultTargetPlatform) {
      TargetPlatform.android => androidAppId,
      TargetPlatform.iOS => iosAppId,
      _ => webAppId,
    };
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
      measurementId: measurementId.isEmpty ? null : measurementId,
    );
  }

  String get emulatorHost {
    if (emulatorHostOverride?.isNotEmpty ?? false) {
      return emulatorHostOverride!;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }
}

final firebaseRuntimeConfigProvider = Provider<FirebaseRuntimeConfig>((ref) {
  return FirebaseRuntimeConfig.fromEnvironment();
});
