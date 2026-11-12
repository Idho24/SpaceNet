import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../data/repositories/otp_repository.dart';
import 'registration_controller.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  final bool verifyOtp;

  const RegistrationScreen({super.key, this.verifyOtp = false});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _customerIdController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(registrationControllerProvider.notifier)
        .requestOtp(
          customerId: _customerIdController.text,
          phoneNumber: _phoneController.text,
        );
    if (!mounted) return;
    final state = ref.read(registrationControllerProvider);
    if (state.status == RegistrationStatus.codeSent) {
      context.go('/verify');
    } else if (state.errorMessage != null) {
      showAppMessage(context, state.errorMessage!);
    }
  }

  Future<void> _verifyOtp() async {
    final success = await ref
        .read(registrationControllerProvider.notifier)
        .verifyOtp(_otpController.text);
    if (!mounted) return;

    if (success) {
      // Auth state sudah diperbarui oleh RegistrationController.verifyOtp()
      // (linkCustomer + refreshCurrentUser). Router redirect akan otomatis
      // mengarahkan ke /home karena user sudah isCustomerLinked.
      // Gunakan WidgetsBinding untuk memastikan state sudah propagate
      // sebelum navigasi.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/home');
      });
      return;
    }

    final state = ref.read(registrationControllerProvider);
    if (state.errorMessage != null) {
      showAppMessage(context, state.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = ref.watch(registrationControllerProvider);
    final otpRepository = ref.watch(otpRepositoryProvider);
    final verifying = widget.verifyOtp;
    final isBusy =
        registration.status == RegistrationStatus.sendingCode ||
        registration.status == RegistrationStatus.verifying;

    return Scaffold(
      appBar: AppBar(
        title: Text(verifying ? 'Verifikasi nomor' : 'Hubungkan pelanggan'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    height: 82,
                    width: 82,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      verifying ? Icons.sms_outlined : Icons.link_rounded,
                      color: AppTheme.primaryBlue,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    verifying
                        ? 'Masukkan kode OTP'
                        : 'Verifikasi data pelanggan',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    verifying
                        ? 'Kode verifikasi dikirim ke ${_maskPhone(registration.phoneNumber)}.'
                        : 'Hubungkan akun Google dengan ID pelanggan dan nomor '
                              'ponsel SpaceNet yang terdaftar.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (verifying) ...[
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Kode OTP',
                        prefixIcon: Icon(Icons.password_outlined),
                        counterText: '',
                      ),
                      validator: (value) =>
                          value == null ||
                              !RegExp(r'^\d{6}$').hasMatch(value.trim())
                          ? 'Masukkan kode OTP 6 digit'
                          : null,
                    ),
                    if (kDebugMode && otpRepository.isDemo && registration.debugOtp != null) ...[
                      const SizedBox(height: 14),
                      _OtpDebugCard(code: registration.debugOtp!),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isBusy
                            ? null
                            : () => ref
                                  .read(registrationControllerProvider.notifier)
                                  .requestOtp(
                                    customerId: registration.customerId,
                                    phoneNumber: registration.phoneNumber,
                                  ),
                        child: const Text('Kirim ulang kode'),
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _customerIdController,
                      decoration: const InputDecoration(
                        labelText: 'ID pelanggan',
                        hintText: 'Contoh: 0012995',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (value) =>
                          value == null ||
                              !RegExp(r'^[A-Za-z0-9_-]{1,40}$')
                                  .hasMatch(value.trim())
                          ? 'Masukkan ID pelanggan yang valid'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Nomor ponsel terdaftar',
                        hintText: '+62 812 0000 0000',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (value) =>
                          value == null ||
                              normalizeRegistrationPhone(value).length < 9
                          ? 'Masukkan nomor ponsel yang valid'
                          : null,
                    ),
                  ],
                  if (registration.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      registration.errorMessage!,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: isBusy
                        ? null
                        : verifying
                        ? _verifyOtp
                        : _sendOtp,
                    child: isBusy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.white,
                            ),
                          )
                        : Text(
                            verifying
                                ? 'Verifikasi & hubungkan akun'
                                : 'Kirim kode verifikasi',
                          ),
                  ),
                  const SizedBox(height: 14),
                  _OtpModeNotice(description: otpRepository.description),
                  TextButton(
                    onPressed: isBusy ? null : () => context.go('/login'),
                    child: const Text('Kembali ke login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length < 6) return phone;
    return '${phone.substring(0, 4)}••••${phone.substring(phone.length - 3)}';
  }
}

String normalizeRegistrationPhone(String phone) {
  // Izinkan karakter bintang untuk nomor dummy di database
  final cleaned = phone.replaceAll(RegExp(r'[^0-9+*]'), '');
  if (cleaned.startsWith('+')) return cleaned.substring(1);
  if (cleaned.startsWith('0')) return '62${cleaned.substring(1)}';
  return cleaned;
}

class _OtpDebugCard extends StatelessWidget {
  final String code;

  const _OtpDebugCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_mode, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'OTP lokal untuk pengujian: $code',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpModeNotice extends StatelessWidget {
  final String description;

  const _OtpModeNotice({required this.description});

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
          const Icon(
            Icons.info_outline,
            color: AppTheme.secondaryBlue,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
