import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_runtime_config.dart';
import 'customer_repository.dart';

class PhoneVerification {
  final String phoneNumber;
  final AuthCredential? credential;
  final bool localMock;

  const PhoneVerification({
    required this.phoneNumber,
    required this.credential,
    required this.localMock,
  });
}

abstract interface class OtpRepository {
  bool get isDemo;
  bool get isEmulator;
  String? get debugCode;
  Future<void> sendCode(String phoneNumber);
  Future<PhoneVerification> verifyCode(String code);
}

class OtpUnavailableException implements Exception {
  final String message;

  const OtpUnavailableException(this.message);

  @override
  String toString() => message;
}

class MockOtpService implements OtpRepository {
  final int? fixedCode;
  String? _phoneNumber;
  String? _code;
  DateTime? _expiresAt;
  int _failedAttempts = 0;

  MockOtpService({this.fixedCode});

  @override
  bool get isDemo => true;

  @override
  bool get isEmulator => false;

  @override
  String? get debugCode => _code;

  @override
  Future<void> sendCode(String phoneNumber) async {
    final normalizedPhone = normalizePhone(phoneNumber);
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone)) {
      throw const FormatException(
        'Nomor ponsel harus menggunakan format internasional.',
      );
    }
    _phoneNumber = normalizedPhone;
    _code = (fixedCode ?? (100000 + Random.secure().nextInt(900000)))
        .toString()
        .padLeft(6, '0');
    _expiresAt = DateTime.now().add(const Duration(minutes: 3));
    _failedAttempts = 0;
    if (kDebugMode) {
      debugPrint('SpaceNet local OTP for development: $_code');
    }
  }

  @override
  Future<PhoneVerification> verifyCode(String code) async {
    final phone = _phoneNumber;
    final expectedCode = _code;
    final expiry = _expiresAt;
    if (phone == null || expectedCode == null || expiry == null) {
      throw const FormatException('Minta kode OTP terlebih dahulu.');
    }
    if (DateTime.now().isAfter(expiry)) {
      throw const FormatException('Kode OTP kedaluwarsa. Minta kode baru.');
    }
    if (_failedAttempts >= 5) {
      throw const FormatException(
        'Percobaan OTP terlalu banyak. Minta kode baru.',
      );
    }
    if (code != expectedCode) {
      _failedAttempts++;
      throw const FormatException('Kode OTP tidak sesuai.');
    }
    _code = null;
    return PhoneVerification(
      phoneNumber: phone,
      credential: null,
      localMock: true,
    );
  }
}

class FirebasePhoneOtpRepository implements OtpRepository {
  final FirebaseAuth _auth;
  String? _phoneNumber;
  String? _verificationId;
  PhoneAuthCredential? _automaticallyVerifiedCredential;
  ConfirmationResult? _webConfirmation;

  FirebasePhoneOtpRepository(this._auth);

  @override
  bool get isDemo => false;

  @override
  bool get isEmulator => true;

  @override
  String? get debugCode => null;

  @override
  Future<void> sendCode(String phoneNumber) async {
    final normalizedPhone = normalizePhone(phoneNumber);
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone)) {
      throw const FormatException(
        'Nomor ponsel harus menggunakan format internasional.',
      );
    }
    _phoneNumber = normalizedPhone;
    _verificationId = null;
    _automaticallyVerifiedCredential = null;

    if (kIsWeb) {
      _webConfirmation = await _auth.signInWithPhoneNumber(normalizedPhone);
      _verificationId = _webConfirmation!.verificationId;
      return;
    }

    final completer = Completer<void>();
    await _auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      verificationCompleted: (credential) {
        _automaticallyVerifiedCredential = credential;
        if (!completer.isCompleted) completer.complete();
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (verificationId, forceResendingToken) {
        _verificationId = verificationId;
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(seconds: 60),
    );
    await completer.future;
  }

  @override
  Future<PhoneVerification> verifyCode(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException('Masukkan kode OTP 6 digit.');
    }
    final phone = _phoneNumber;
    if (phone == null) {
      throw const FormatException('Minta kode OTP terlebih dahulu.');
    }

    final autoCredential = _automaticallyVerifiedCredential;
    final verificationId = _verificationId ?? _webConfirmation?.verificationId;
    if (autoCredential == null &&
        (verificationId == null || verificationId.isEmpty)) {
      throw const FormatException('Sesi OTP tidak valid. Minta kode baru.');
    }
    final credential =
        autoCredential ??
        PhoneAuthProvider.credential(
          verificationId: verificationId!,
          smsCode: code,
        );
    return PhoneVerification(
      phoneNumber: phone,
      credential: credential,
      localMock: false,
    );
  }
}

class ProductionOtpDisabledRepository implements OtpRepository {
  static const _message =
      'OTP SMS produksi dinonaktifkan agar tidak menimbulkan biaya. '
      'Gunakan Firebase Auth Emulator untuk pengujian.';

  @override
  bool get isDemo => false;

  @override
  bool get isEmulator => false;

  @override
  String? get debugCode => null;

  @override
  Future<void> sendCode(String phoneNumber) async {
    throw const OtpUnavailableException(_message);
  }

  @override
  Future<PhoneVerification> verifyCode(String code) async {
    throw const OtpUnavailableException(_message);
  }
}

final otpRepositoryProvider = Provider<OtpRepository>((ref) {
  final config = ref.watch(firebaseRuntimeConfigProvider);
  if (config.isConfigured && config.useEmulators) {
    return FirebasePhoneOtpRepository(FirebaseAuth.instance);
  }
  return config.isConfigured
      ? ProductionOtpDisabledRepository()
      : MockOtpService();
});
