import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/otp_repository.dart';
import 'auth_state.dart';

enum RegistrationStatus {
  idle,
  sendingCode,
  codeSent,
  verifying,
  linked,
  error,
}

class RegistrationState {
  final RegistrationStatus status;
  final String customerId;
  final String phoneNumber;
  final String? debugOtp;
  final String? errorMessage;

  const RegistrationState({
    this.status = RegistrationStatus.idle,
    this.customerId = '',
    this.phoneNumber = '',
    this.debugOtp,
    this.errorMessage,
  });

  RegistrationState copyWith({
    RegistrationStatus? status,
    String? customerId,
    String? phoneNumber,
    String? debugOtp,
    String? errorMessage,
    bool clearDebugOtp = false,
    bool clearError = false,
  }) {
    return RegistrationState(
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      debugOtp: clearDebugOtp ? null : debugOtp ?? this.debugOtp,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class RegistrationController extends StateNotifier<RegistrationState> {
  final OtpRepository _otp;
  final AuthNotifier _auth;

  RegistrationController(this._otp, this._auth)
    : super(const RegistrationState());

  Future<void> requestOtp({
    required String customerId,
    required String phoneNumber,
  }) async {
    final normalizedCustomerId = customerId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(normalizedCustomerId)) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'ID pelanggan tidak valid.',
        clearDebugOtp: true,
      );
      return;
    }
    final normalizedPhone = normalizePhone(phoneNumber);
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone)) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'Masukkan nomor ponsel dengan kode negara, misalnya +62.',
        clearDebugOtp: true,
      );
      return;
    }

    state = state.copyWith(
      status: RegistrationStatus.sendingCode,
      customerId: normalizedCustomerId,
      phoneNumber: normalizedPhone,
      clearDebugOtp: true,
      clearError: true,
    );
    try {
      await _otp.sendCode(normalizedPhone);
      state = state.copyWith(
        status: RegistrationStatus.codeSent,
        debugOtp: _otp.debugCode,
      );
    } on OtpUnavailableException catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: error.message,
      );
    } on FormatException catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: error.message,
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'Kode OTP tidak dapat dikirim. ${error.toString()}',
      );
    }
  }

  Future<bool> verifyOtp(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'Masukkan kode OTP 6 digit.',
      );
      return false;
    }
    if (state.customerId.isEmpty || state.phoneNumber.isEmpty) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'Data pelanggan tidak tersedia. Mulai validasi kembali.',
      );
      return false;
    }

    state = state.copyWith(
      status: RegistrationStatus.verifying,
      clearError: true,
    );
    try {
      final verification = await _otp.verifyCode(code.trim());
      await _auth.linkCustomer(
        customerId: state.customerId,
        verification: verification,
      );
      await _auth.refreshCurrentUser();
      state = state.copyWith(
        status: RegistrationStatus.linked,
        clearDebugOtp: true,
      );
      return true;
    } on CustomerLinkException catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: error.message,
      );
    } on OtpUnavailableException catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: error.message,
      );
    } on FormatException catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: error.message,
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        errorMessage: 'Verifikasi gagal. ${error.toString()}',
      );
    }
    return false;
  }
}

final registrationControllerProvider =
    StateNotifierProvider<RegistrationController, RegistrationState>((ref) {
      return RegistrationController(
        ref.watch(otpRepositoryProvider),
        ref.watch(authNotifierProvider.notifier),
      );
    });
