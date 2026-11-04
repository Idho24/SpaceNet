import 'package:flutter_riverpod/flutter_riverpod.dart';

class SupabaseRuntimeConfig {
  final String url;
  final String publishableKey;
  final bool enablePhoneOtp;

  const SupabaseRuntimeConfig({
    required this.url,
    required this.publishableKey,
    this.enablePhoneOtp = false,
  });

  factory SupabaseRuntimeConfig.fromEnvironment() {
    const publishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: '',
    );
    const legacyAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );

    return SupabaseRuntimeConfig(
      url: const String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
      publishableKey: publishableKey.isNotEmpty
          ? publishableKey
          : legacyAnonKey,
      enablePhoneOtp: const bool.fromEnvironment(
        'SUPABASE_ENABLE_PHONE_OTP',
        defaultValue: false,
      ),
    );
  }

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}

final supabaseRuntimeConfigProvider = Provider<SupabaseRuntimeConfig>((ref) {
  return SupabaseRuntimeConfig.fromEnvironment();
});

final supabaseStartupErrorProvider = Provider<String?>((ref) => null);
