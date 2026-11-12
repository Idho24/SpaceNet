import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_runtime_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/brand_logo.dart';
import 'auth_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  Future<void> _startAccountConnection(SupabaseRuntimeConfig config) async {
    final auth = ref.read(authNotifierProvider.notifier);
    if (!config.isConfigured || config.isTestingMode) {
      await auth.signInDemo();
    } else {
      await auth.signInWithGoogle();
    }
  }

  void _showHelp({required bool isLoading, required bool showDemoAction}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Butuh bantuan?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              const Text(
                'Masuk menggunakan akun Google Anda. Setelah berhasil masuk, '
                'siapkan ID pelanggan dan nomor ponsel yang terdaftar untuk '
                'menghubungkan layanan SpaceNet.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        ref
                            .read(authNotifierProvider.notifier)
                            .signInWithGoogle();
                      },
                icon: const Icon(Icons.login_rounded),
                label: const Text('Mulai login dengan Google'),
              ),
              if (showDemoAction) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          ref.read(authNotifierProvider.notifier).signInDemo();
                        },
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Masuk mode demo lokal'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(supabaseRuntimeConfigProvider);
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.status == AuthStatus.loading;

    ref.listen(authNotifierProvider, (previous, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LoginBackgroundPainter()),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.min(700.0, constraints.maxWidth - 56);
                final logoWidth = contentWidth >= 500
                    ? 420.0
                    : contentWidth * 0.78;
                final titleSize = (contentWidth * 0.09).clamp(34.0, 56.0);
                final bodySize = (contentWidth * 0.04).clamp(18.0, 26.0);
                final buttonHeight = constraints.maxWidth >= 600 ? 82.0 : 60.0;
                final topSpace = (constraints.maxHeight * 0.22).clamp(
                  36.0,
                  248.0,
                );

                return SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 700,
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: topSpace),
                            Center(child: BrandLogo(width: logoWidth)),
                            SizedBox(height: contentWidth >= 500 ? 58 : 40),
                            Text(
                              'Selamat datang',
                              style: Theme.of(context).textTheme.displayLarge
                                  ?.copyWith(
                                    fontSize: titleSize,
                                    height: 1.1,
                                    letterSpacing: -1,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Masuk dengan akun Google untuk mengelola '
                              'layanan internet Anda.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF526987),
                                    fontSize: bodySize,
                                    height: 1.45,
                                    fontWeight: FontWeight.w400,
                                  ),
                            ),
                            SizedBox(height: contentWidth >= 500 ? 46 : 32),
                            SizedBox(
                              height: buttonHeight,
                              child: ElevatedButton(
                                onPressed: isLoading
                                    ? null
                                    : () => ref
                                          .read(authNotifierProvider.notifier)
                                          .signInWithGoogle(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF079FE3),
                                  foregroundColor: AppTheme.white,
                                  elevation: 5,
                                  shadowColor: const Color(0xFF079FE3)
                                      .withValues(alpha: 0.28),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppTheme.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'G',
                                            style: TextStyle(
                                              fontSize: 30,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          Container(
                                            height: 30,
                                            width: 1.5,
                                            color: AppTheme.white.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          Flexible(
                                            child: Text(
                                              'Lanjutkan dengan Google',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: bodySize * 0.95,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            SizedBox(height: contentWidth >= 500 ? 66 : 42),
                            const Divider(
                              color: Color(0xFF9AAFC8),
                              thickness: 1,
                            ),
                            SizedBox(height: contentWidth >= 500 ? 28 : 20),
                            TextButton(
                              onPressed: isLoading
                                  ? null
                                  : () => _startAccountConnection(config),
                              child: const Text(
                                'Pelanggan baru? Hubungkan akun',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _showHelp(
                                isLoading: isLoading,
                                showDemoAction:
                                    !config.isConfigured ||
                                    config.isTestingMode,
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
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackgroundPainter extends CustomPainter {
  const _LoginBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF9FCFF), Color(0xFFF2F8FD)],
        ).createShader(rect),
    );

    final topShapes = [
      (
        Color(0xFFBDE6FF),
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width * 0.43, 0)
          ..cubicTo(
            size.width * 0.34,
            size.height * 0.08,
            size.width * 0.16,
            size.height * 0.14,
            0,
            size.height * 0.20,
          )
          ..close(),
      ),
      (
        Color(0xFFD8F0FF),
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width * 0.56, 0)
          ..cubicTo(
            size.width * 0.43,
            size.height * 0.11,
            size.width * 0.20,
            size.height * 0.18,
            0,
            size.height * 0.25,
          )
          ..close(),
      ),
    ];
    for (final (color, path) in topShapes) {
      canvas.drawPath(path, Paint()..color = color);
    }

    final bottomShapes = [
      (
        Color(0xFFDFF2FF),
        Path()
          ..moveTo(size.width * 0.42, size.height)
          ..cubicTo(
            size.width * 0.64,
            size.height * 0.88,
            size.width * 0.79,
            size.height * 0.80,
            size.width,
            size.height * 0.76,
          )
          ..lineTo(size.width, size.height)
          ..close(),
      ),
      (
        Color(0xFFB8E5FF),
        Path()
          ..moveTo(size.width * 0.57, size.height)
          ..cubicTo(
            size.width * 0.72,
            size.height * 0.88,
            size.width * 0.87,
            size.height * 0.84,
            size.width,
            size.height * 0.82,
          )
          ..lineTo(size.width, size.height)
          ..close(),
      ),
      (
        Color(0xFF8FD4FF),
        Path()
          ..moveTo(size.width * 0.72, size.height)
          ..cubicTo(
            size.width * 0.85,
            size.height * 0.92,
            size.width * 0.94,
            size.height * 0.90,
            size.width,
            size.height * 0.88,
          )
          ..lineTo(size.width, size.height)
          ..close(),
      ),
    ];
    for (final (color, path) in bottomShapes) {
      canvas.drawPath(path, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
