import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';
import 'customer_repository.dart';

class PhoneVerification {
  final String phoneNumber;
  final Object? credential;
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
  String get description;
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
  String get description =>
      'OTP lokal hanya untuk demo dan tidak dapat menghubungkan akun backend.';

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

class ProductionOtpDisabledRepository implements OtpRepository {
  static const _message =
      'OTP SMS produksi dinonaktifkan agar tidak menimbulkan biaya. '
      'Gunakan mode demo untuk pengujian.';

  @override
  bool get isDemo => false;

  @override
  bool get isEmulator => false;

  @override
  String? get debugCode => null;

  @override
  String get description =>
      'OTP SMS dinonaktifkan. Aktifkan secara eksplisit setelah mengatur '
      'provider atau nomor uji Supabase Auth.';

  @override
  Future<void> sendCode(String phoneNumber) async {
    throw const OtpUnavailableException(_message);
  }

  @override
  Future<PhoneVerification> verifyCode(String code) async {
    throw const OtpUnavailableException(_message);
  }
}

class SupabasePhoneOtpRepository implements OtpRepository {
  final SupabaseClient _client;
  String? _phoneNumber;

  SupabasePhoneOtpRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  bool get isDemo => false;

  @override
  bool get isEmulator => false;

  @override
  String? get debugCode => null;

  @override
  String get description =>
      'Kode dikirim melalui provider SMS Supabase yang dikonfigurasi proyek.';

  @override
  Future<void> sendCode(String phoneNumber) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const OtpUnavailableException(
        'Masuk terlebih dahulu sebelum memverifikasi nomor ponsel.',
      );
    }
    final normalizedPhone = normalizePhone(phoneNumber);
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone)) {
      throw const FormatException(
        'Nomor ponsel harus menggunakan format internasional.',
      );
    }
    await _client.auth.updateUser(UserAttributes(phone: normalizedPhone));
    _phoneNumber = normalizedPhone;
  }

  @override
  Future<PhoneVerification> verifyCode(String code) async {
    final phone = _phoneNumber;
    if (phone == null) {
      throw const FormatException('Minta kode OTP terlebih dahulu.');
    }
    final response = await _client.auth.verifyOTP(
      phone: phone,
      token: code,
      type: OtpType.phoneChange,
    );
    final user = response.user ?? _client.auth.currentUser;
    if (user == null ||
        user.phoneConfirmedAt == null ||
        user.phone == null ||
        normalizePhone(user.phone!) != phone) {
      throw const FormatException(
        'Supabase belum mengonfirmasi nomor ponsel. Coba verifikasi kembali.',
      );
    }
    _phoneNumber = null;
    return PhoneVerification(
      phoneNumber: phone,
      credential: user,
      localMock: false,
    );
  }
}

/// OTP service untuk mode pengujian dengan validasi terhadap database Supabase.
/// Mengecek bahwa customer_id + phone cocok di tabel customers sebelum
/// mengeluarkan kode OTP lokal (mock). Tidak memerlukan SMS provider.
class TestingOtpService implements OtpRepository {
  final SupabaseClient? _client;
  final int? fixedCode;
  String? _phoneNumber;
  String? _customerId;
  String? _code;
  DateTime? _expiresAt;
  int _failedAttempts = 0;

  TestingOtpService({this.fixedCode, SupabaseClient? client})
    : _client = client ?? _safeSupabaseClient();

  @override
  bool get isDemo => true;

  @override
  bool get isEmulator => false;

  @override
  String? get debugCode => _code;

  @override
  String get description =>
      'Mode pengujian: OTP lokal dengan validasi data pelanggan dari database.';

  /// Di testing mode, sendCode perlu customer_id untuk validasi.
  /// Customer ID disimpan sebelum sendCode dipanggil oleh RegistrationController.
  void setCustomerId(String customerId) {
    _customerId = customerId;
  }

  @override
  Future<void> sendCode(String phoneNumber) async {
    final normalizedPhone = normalizePhone(phoneNumber);
    // Di mode pengujian, izinkan nomor yang mengandung '*' jika user mengetik data dummy dari DB
    final isMaskedPhone = phoneNumber.contains('*');
    if (!isMaskedPhone && !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone)) {
      throw const FormatException(
        'Nomor ponsel harus menggunakan format internasional.',
      );
    }

    // Validasi customer_id + phone terhadap database Supabase
    final c = _client;
    final cid = _customerId;
    if (c != null && cid != null && cid.isNotEmpty) {
      try {
        final isValid = await c.rpc('validate_customer_phone', params: {
          'p_customer_id': cid,
          'p_phone': phoneNumber.trim(),
        });
        if (isValid != true) {
          throw const FormatException(
            'ID pelanggan dan nomor ponsel tidak cocok. '
            'Periksa data yang terdaftar di database.',
          );
        }
      } on PostgrestException catch (e) {
        // Jika RPC belum ada, coba query langsung ke tabel customers
        if (e.message.contains('function') &&
            e.message.contains('does not exist')) {
          if (kDebugMode) {
            debugPrint(
              'validate_customer_phone RPC not found, trying direct query.',
            );
          }
          await _validateCustomerPhoneDirect(c, cid, normalizedPhone);
        } else {
          throw FormatException(
            'Gagal memvalidasi data pelanggan: ${e.message}',
          );
        }
      }
    }

    _phoneNumber = normalizedPhone;
    _code = (fixedCode ?? (100000 + Random.secure().nextInt(900000)))
        .toString()
        .padLeft(6, '0');
    _expiresAt = DateTime.now().add(const Duration(minutes: 3));
    _failedAttempts = 0;
    if (kDebugMode) {
      debugPrint('SpaceNet testing OTP: $_code (for $normalizedPhone)');
    }
  }

  /// Validasi langsung ke tabel customers jika RPC belum ada.
  Future<void> _validateCustomerPhoneDirect(
    SupabaseClient client,
    String customerId,
    String normalizedPhone,
  ) async {
    try {
      final response = await client
          .from('customers')
          .select('customer_id, phone')
          .eq('customer_id', customerId)
          .maybeSingle();

      if (response == null) {
        throw const FormatException(
          'ID pelanggan tidak ditemukan di database.',
        );
      }

      final dbPhone = response['phone'] as String?;
      if (dbPhone == null || dbPhone.isEmpty) {
        throw const FormatException(
          'Data nomor ponsel pelanggan tidak tersedia di database.',
        );
      }

      // Bandingkan nomor ponsel: normalisasi kedua sisi
      if (normalizePhone(dbPhone) != normalizedPhone) {
        throw const FormatException(
          'ID pelanggan dan nomor ponsel tidak cocok. '
          'Periksa data yang terdaftar di database.',
        );
      }
    } on FormatException {
      rethrow;
    } on PostgrestException catch (e) {
      // Jika tabel customers tidak bisa diakses (RLS), lanjutkan tanpa validasi
      if (kDebugMode) {
        debugPrint(
          'Direct query to customers table failed (possibly RLS): ${e.message}',
        );
      }
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

SupabaseClient? _safeSupabaseClient() {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

final otpRepositoryProvider = Provider<OtpRepository>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (config.isTestingMode && config.isConfigured) {
    return TestingOtpService();
  }
  if (!config.isConfigured) return MockOtpService();
  if (!config.enablePhoneOtp) return ProductionOtpDisabledRepository();
  return SupabasePhoneOtpRepository();
});
