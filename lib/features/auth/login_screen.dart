import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/firebase/firebase_runtime_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/brand_logo.dart';
import 'auth_state.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebaseConfigured = ref.watch(firebaseRuntimeConfigProvider).isConfigured;
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    ref.listen(authNotifierProvider, (previous, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(width: 260)),
                  const SizedBox(height: 32),
                  Text(
                    'Selamat datang',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Masuk dengan akun Google untuk mengelola layanan internet Anda.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => ref
                            .read(authNotifierProvider.notifier)
                            .signInWithGoogle(),
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.white,
                            ),
                          )
                        : const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: Text(
                      isLoading
                          ? 'Menghubungkan...'
                          : 'Lanjutkan dengan Google',
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!firebaseConfigured) ...[
                    OutlinedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => ref
                              .read(authNotifierProvider.notifier)
                              .signInDemo(),
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Masuk mode demo lokal'),
                    ),
                    const SizedBox(height: 14),
                    const _AuthNotice(
                      message:
                          'Firebase belum dikonfigurasi. Tombol Google hanya berfungsi '
                          'setelah konfigurasi lokal tersedia; mode demo memakai data lokal.',
                    ),
                  ] else ...[
                    const _AuthNotice(
                      message:
                          'Login menggunakan Firebase Authentication. Akun baru akan '
                          'diminta menghubungkan ID pelanggan dan memverifikasi nomor ponsel.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => context.push('/register'),
                    child: const Text('Pelanggan baru? Hubungkan akun'),
                  ),
                  TextButton.icon(
                    onPressed: () => showAppMessage(
                      context,
                      'Hubungi dukungan SpaceNet melalui nomor resmi perusahaan.',
                    ),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Butuh bantuan?'),
                  ),
                  if (authState.status == AuthStatus.error &&
                      authState.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      authState.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthNotice extends StatelessWidget {
  final String message;

  const _AuthNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.secondaryBlue, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
