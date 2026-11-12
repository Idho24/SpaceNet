import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SupabaseRuntimeConfig {
  final String url;
  final String publishableKey;
  final bool enablePhoneOtp;
  final bool isTestingMode;

  const SupabaseRuntimeConfig({
    required this.url,
    required this.publishableKey,
    this.enablePhoneOtp = false,
    this.isTestingMode = false,
  });

  // Default proyek SpaceNet. Publishable key aman untuk client; akses data
  // tetap dibatasi RLS. Nilai ini bisa ditimpa lewat --dart-define.
  static const defaultUrl = 'https://jenqyryusfuxgswvftvc.supabase.co';
  static const defaultPublishableKey =
      'sb_publishable_mlIRgdhFzl3CJKyseyQ97A_zkhDMJYn';

  factory SupabaseRuntimeConfig.fromEnvironment() {
    const publishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: '',
    );
    const legacyAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );

    final testingEnv = const bool.fromEnvironment(
      'SUPABASE_TESTING_MODE',
      defaultValue: true,
    );

    return SupabaseRuntimeConfig(
      url: const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: defaultUrl,
      ),
      publishableKey: publishableKey.isNotEmpty
          ? publishableKey
          : legacyAnonKey.isNotEmpty
          ? legacyAnonKey
          : defaultPublishableKey,
      enablePhoneOtp: const bool.fromEnvironment(
        'SUPABASE_ENABLE_PHONE_OTP',
        defaultValue: false,
      ),
      isTestingMode: kDebugMode && testingEnv,
    );
  }

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

final supabaseRuntimeConfigProvider = Provider<SupabaseRuntimeConfig>((ref) {
  return SupabaseRuntimeConfig.fromEnvironment();
});

final supabaseStartupErrorProvider = Provider<String?>((ref) => null);
