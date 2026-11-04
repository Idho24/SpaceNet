import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';
import 'customer_repository.dart';
import 'otp_repository.dart';

class AuthSessionUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? customerId;

  const AuthSessionUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.customerId,
  });

  bool get isCustomerLinked => customerId != null;
}

abstract interface class AuthRepository {
  bool get isDemo;
  AuthSessionUser? get currentSession;
  Stream<AuthSessionUser?> get authStateChanges;
  Future<void> signInWithGoogle();
  Future<AuthSessionUser> signInDemo();
  Future<void> signOut();
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  });
  Future<AuthSessionUser?> refreshCurrentUser();
}

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient _client;
  final CustomerRepository customers;

  SupabaseAuthRepository({SupabaseClient? client, required this.customers})
    : _client = client ?? Supabase.instance.client;

  @override
  bool get isDemo => false;

  @override
  AuthSessionUser? get currentSession {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return AuthSessionUser(
      uid: user.id,
      email: user.email,
      displayName: user.userMetadata?['full_name'] as String?,
      photoUrl: user.userMetadata?['avatar_url'] as String?,
      customerId: null,
    );
  }

  @override
  Stream<AuthSessionUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.asyncMap((state) {
        final user = state.session?.user;
        if (user == null) return null;
        return _sessionForUser(user);
      });

  @override
  Future<void> signInWithGoogle() async {
    final result = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.spacenet.mobile://login-callback',
    );
    if (!result) {
      throw StateError('Google Sign-In gagal dibuka.');
    }
  }

  @override
  Future<AuthSessionUser> signInDemo() {
    throw UnsupportedError('Akun demo hanya tersedia tanpa Supabase.');
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  }) async {
    if (verification.localMock) {
      throw const CustomerLinkException(
        'OTP demo lokal tidak dapat digunakan untuk menghubungkan akun Supabase.',
      );
    }

    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw const CustomerLinkException('Sesi login berakhir.');
    }

    final normalizedPhone = normalizePhone(verification.phoneNumber);
    if (currentUser.phoneConfirmedAt == null ||
        currentUser.phone == null ||
        normalizePhone(currentUser.phone!) != normalizedPhone) {
      throw const CustomerLinkException(
        'Verifikasi nomor ponsel melalui Supabase Auth sebelum menghubungkan akun.',
      );
    }

    await customers.linkCustomer(
      uid: currentUser.id,
      customerId: customerId,
      verifiedPhone: normalizedPhone,
    );

    return _sessionForUser(currentUser);
  }

  @override
  Future<AuthSessionUser?> refreshCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _sessionForUser(user);
  }

  Future<AuthSessionUser> _sessionForUser(User user) async {
    final customerId = await customers.linkedCustomerId(user.id);
    return AuthSessionUser(
      uid: user.id,
      email: user.email,
      displayName:
          user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String?,
      photoUrl: user.userMetadata?['avatar_url'] as String?,
      customerId: customerId,
    );
  }
}

class MockAuthRepository implements AuthRepository {
  final CustomerRepository _customers;
  final StreamController<AuthSessionUser?> _changes =
      StreamController<AuthSessionUser?>.broadcast();
  AuthSessionUser? _session;

  MockAuthRepository(this._customers);

  @override
  bool get isDemo => true;

  @override
  AuthSessionUser? get currentSession => _session;

  @override
  Stream<AuthSessionUser?> get authStateChanges async* {
    yield _session;
    yield* _changes.stream;
  }

  @override
  Future<AuthSessionUser> signInDemo() async {
    _session = const AuthSessionUser(
      uid: 'local-preview-user',
      email: 'customer@spacenet.id',
      displayName: 'Nabila Sari',
      photoUrl: null,
      customerId: null,
    );
    _changes.add(_session);
    return _session!;
  }

  @override
  Future<void> signInWithGoogle() async {
    throw UnsupportedError(
      'Supabase Google Sign-In belum dikonfigurasi. Gunakan mode demo lokal.',
    );
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _changes.add(null);
  }

  @override
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  }) async {
    final current = _session;
    if (current == null) {
      throw const CustomerLinkException('Sesi login berakhir.');
    }
    if (!verification.localMock) {
      throw const CustomerLinkException('Bukti OTP demo tidak valid.');
    }
    await _customers.linkCustomer(
      uid: current.uid,
      customerId: customerId,
      verifiedPhone: verification.phoneNumber,
    );
    _session = AuthSessionUser(
      uid: current.uid,
      email: current.email,
      displayName: current.displayName,
      photoUrl: current.photoUrl,
      customerId: customerId,
    );
    _changes.add(_session);
    return _session!;
  }

  @override
  Future<AuthSessionUser?> refreshCurrentUser() async {
    final current = _session;
    if (current == null) return null;
    final customerId = await _customers.linkedCustomerId(current.uid);
    _session = AuthSessionUser(
      uid: current.uid,
      email: current.email,
      displayName: current.displayName,
      photoUrl: current.photoUrl,
      customerId: customerId,
    );
    return _session;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  final customers = ref.watch(customerRepositoryProvider);
  if (config.isConfigured) {
    return SupabaseAuthRepository(customers: customers);
  }
  return MockAuthRepository(customers);
});
