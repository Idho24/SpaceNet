import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/firebase/firebase_bootstrap.dart';
import 'core/firebase/firebase_runtime_config.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = FirebaseRuntimeConfig.fromEnvironment();
  String? startupError;

  if (config.isConfigured) {
    try {
      await FirebaseBootstrap.initialize(config);
    } on FirebaseException catch (error) {
      startupError =
          'Firebase gagal diinisialisasi (${error.code}). Periksa konfigurasi lokal.';
    } on StateError catch (error) {
      startupError = error.message;
    } on Exception catch (error) {
      startupError = 'Firebase gagal diinisialisasi: $error';
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        firebaseRuntimeConfigProvider.overrideWithValue(config),
        firebaseStartupErrorProvider.overrideWithValue(startupError),
      ],
      child: const SpaceNetApp(),
    ),
  );
}

class SpaceNetApp extends ConsumerWidget {
  const SpaceNetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupError = ref.watch(firebaseStartupErrorProvider);
    if (startupError != null) {
      return MaterialApp(
        title: 'SpaceNet Mobile',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: _FirebaseStartupErrorScreen(message: startupError),
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

class _FirebaseStartupErrorScreen extends StatelessWidget {
  final String message;

  const _FirebaseStartupErrorScreen({required this.message});

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
                    'Koneksi Firebase belum siap',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Perbaiki konfigurasi Firebase lokal lalu jalankan ulang aplikasi.',
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
