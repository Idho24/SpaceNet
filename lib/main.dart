import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase/supabase_runtime_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseRuntimeConfig.fromEnvironment();
  String? startupError;

  if (config.isConfigured) {
    try {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
      );
    } on Exception catch (error) {
      startupError = 'Supabase gagal diinisialisasi: $error';
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        supabaseRuntimeConfigProvider.overrideWithValue(config),
        supabaseStartupErrorProvider.overrideWithValue(startupError),
      ],
      child: const SpaceNetApp(),
    ),
  );
}

/// Fungsi untuk menangani proses Google Sign-In dan autentikasi ke Supabase
Future<AuthResponse> signInWithGoogle() async {
  final GoogleSignIn googleSignIn = GoogleSignIn();
  final googleUser = await googleSignIn.signIn();

  if (googleUser == null) {
    throw Exception('Proses login Google dibatalkan oleh pengguna.');
  }

  final googleAuth = await googleUser.authentication;
  final accessToken = googleAuth.accessToken;
  final idToken = googleAuth.idToken;

  if (accessToken == null || accessToken.isEmpty) {
    throw Exception('Gagal mendapatkan Access Token dari Google.');
  }

  if (idToken == null || idToken.isEmpty) {
    throw Exception('Gagal mendapatkan ID Token dari Google.');
  }

  return await Supabase.instance.client.auth.signInWithIdToken(
    provider: OAuthProvider.google,
    idToken: idToken,
    accessToken: accessToken,
  );
}

class SpaceNetApp extends ConsumerWidget {
  const SpaceNetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupError = ref.watch(supabaseStartupErrorProvider);
    if (startupError != null) {
      return MaterialApp(
        title: 'SpaceNet Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: _SupabaseStartupErrorScreen(message: startupError),
      );
    }

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'SpaceNet Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class _SupabaseStartupErrorScreen extends StatelessWidget {
  final String message;

  const _SupabaseStartupErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: AppTheme.error,
                    size: 52,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Koneksi Supabase belum siap',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Perbaiki konfigurasi Supabase lokal lalu jalankan ulang aplikasi.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}