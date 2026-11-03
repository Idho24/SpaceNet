import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_runtime_config.dart';

final firebaseStartupErrorProvider = Provider<String?>((ref) => null);

class FirebaseBootstrap {
  static Future<void> initialize(FirebaseRuntimeConfig config) async {
    await Firebase.initializeApp(options: config.firebaseOptions);

    if (config.useEmulators) {
      FirebaseAuth.instance.useAuthEmulator(config.emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(
        config.emulatorHost,
        8080,
      );
      return;
    }

    if (config.enableAppCheck) {
      if (kIsWeb && config.appCheckWebSiteKey.isEmpty) {
        throw StateError(
          'FIREBASE_APP_CHECK_WEB_SITE_KEY is required when App Check is enabled on web.',
        );
      }

      await FirebaseAppCheck.instance.activate(
        providerWeb: kIsWeb
            ? ReCaptchaV3Provider(config.appCheckWebSiteKey)
            : null,
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }
  }
}