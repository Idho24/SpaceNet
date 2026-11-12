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

  factory AuthSessionUser.fromSupabaseUser(User user, {String? customerId}) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return AuthSessionUser(
      uid: user.id,
      email: user.email,
      displayName:
          _nonEmptyString(metadata['full_name']) ??
          _nonEmptyString(metadata['name']),
      photoUrl: metadata['avatar_url'] as String?,
      customerId: customerId,
    );
  }

  const AuthSessionUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.customerId,
  });

  bool get isCustomerLinked => customerId != null;
}

String? _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

String _googleOAuthRedirectTo() =>
    kIsWeb ? Uri.base.origin : 'io.spacenet.mobile://login-callback';

abstract interface class AuthRepository {
  bool get isDemo;
  AuthSessionUser? get currentSession;
  Stream<AuthSessionUser?> get authStateChanges;
  Future<void> signInWithGoogle();
  Future<AuthSessionUser> signInDemo();
  Future<void> signOut();
  Future<AuthSessionUser> updateDisplayName(String displayName);
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  });
  Future<AuthSessionUser?> refreshCurrentUser();
}

SupabaseClient? _safeSupabaseClient() {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient? _client;
  final CustomerRepository customers;

  SupabaseAuthRepository({SupabaseClient? client, required this.customers})
    : _client = client ?? _safeSupabaseClient();

  SupabaseClient get client =>
      _client ??
      (throw const CustomerLinkException('Supabase belum diinisialisasi.'));

  @override
  bool get isDemo => false;

  @override
  AuthSessionUser? get currentSession {
    final c = _client;
    if (c == null) return null;
    final user = c.auth.currentUser;
    if (user == null) return null;
    return AuthSessionUser.fromSupabaseUser(user);
  }

  @override
  Stream<AuthSessionUser?> get authStateChanges {
    final c = _client;
    if (c == null) return const Stream.empty();
    return c.auth.onAuthStateChange.asyncMap((state) {
      final user = state.session?.user;
      if (user == null) return null;
      return _sessionForUser(user);
    });
  }

  @override
  Future<void> signInWithGoogle() async {
    final result = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _googleOAuthRedirectTo(),
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
    await client.auth.signOut();
  }

  @override
  Future<AuthSessionUser> updateDisplayName(String displayName) async {
    final response = await client.auth.updateUser(
      UserAttributes(data: {'full_name': displayName}),
    );
    final user = response.user;
    if (user == null) {
      throw StateError('Supabase tidak mengembalikan profil yang diperbarui.');
    }
    return _sessionForUser(user);
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

    final c = client;
    final currentUser = c.auth.currentUser;
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
    final c = _client;
    if (c == null) return null;
    final user = c.auth.currentUser;
    if (user == null) return null;
    return _sessionForUser(user);
  }

  Future<AuthSessionUser> _sessionForUser(User user) async {
    final customerId = await customers.linkedCustomerId(user.id);
    return AuthSessionUser.fromSupabaseUser(user, customerId: customerId);
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
  Future<AuthSessionUser> updateDisplayName(String displayName) async {
    final current = _session;
    if (current == null) {
      throw const CustomerLinkException('Sesi login berakhir.');
    }
    _session = AuthSessionUser(
      uid: current.uid,
      email: current.email,
      displayName: displayName,
      photoUrl: current.photoUrl,
      customerId: current.customerId,
    );
    _changes.add(_session);
    return _session!;
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

/// Auth repository untuk mode pengujian (testing mode) dengan Supabase
/// yang sudah dikonfigurasi. Mendukung login Google (Supabase Auth) DAN
/// mode demo lokal. Mengizinkan verifikasi OTP lokal (mock) saat
/// menghubungkan akun pelanggan — sehingga pengujian tidak membutuhkan
/// SMS provider yang aktif.
class TestingSupabaseAuthRepository implements AuthRepository {
  final SupabaseClient? _client;
  final CustomerRepository customers;
  final StreamController<AuthSessionUser?> _demoChanges =
      StreamController<AuthSessionUser?>.broadcast();
  AuthSessionUser? _demoSession;

  TestingSupabaseAuthRepository({SupabaseClient? client, required this.customers})
    : _client = client ?? _safeSupabaseClient();

  bool get _isDemoActive => _demoSession != null;

  @override
  bool get isDemo => _isDemoActive;

  @override
  AuthSessionUser? get currentSession {
    if (_isDemoActive) return _demoSession;
    final c = _client;
    if (c == null) return null;
    final user = c.auth.currentUser;
    if (user == null) return null;
    return AuthSessionUser.fromSupabaseUser(user);
  }

  @override
  Stream<AuthSessionUser?> get authStateChanges async* {
    if (_isDemoActive) {
      yield _demoSession;
    }
    final controller = StreamController<AuthSessionUser?>.broadcast();

    StreamSubscription? subSupabase;
    final c = _client;
    if (c != null) {
      subSupabase = c.auth.onAuthStateChange.listen((state) async {
        if (_isDemoActive) return;
        final user = state.session?.user;
        if (user == null) {
          controller.add(null);
        } else {
          final session = await _sessionForUser(user);
          controller.add(session);
        }
      });
    }

    final subDemo = _demoChanges.stream.listen((session) {
      controller.add(session);
    });

    try {
      yield* controller.stream;
    } finally {
      await subSupabase?.cancel();
      await subDemo.cancel();
      await controller.close();
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    _demoSession = null;
    final c = _client;
    if (c == null) {
      throw StateError('Supabase belum diinisialisasi.');
    }
    final result = await c.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _googleOAuthRedirectTo(),
    );
    if (!result) {
      throw StateError('Google Sign-In gagal dibuka.');
    }
  }

  @override
  Future<AuthSessionUser> signInDemo() async {
    _demoSession = const AuthSessionUser(
      uid: 'testing-demo-user',
      email: 'testing@spacenet.id',
      displayName: 'Pengguna Uji Coba',
      photoUrl: null,
      customerId: null,
    );
    _demoChanges.add(_demoSession);
    return _demoSession!;
  }

  @override
  Future<void> signOut() async {
    if (_isDemoActive) {
      _demoSession = null;
      _demoChanges.add(null);
    } else {
      await _client?.auth.signOut();
    }
  }

  @override
  Future<AuthSessionUser> updateDisplayName(String displayName) async {
    if (_isDemoActive) {
      final current = _demoSession!;
      _demoSession = AuthSessionUser(
        uid: current.uid,
        email: current.email,
        displayName: displayName,
        photoUrl: current.photoUrl,
        customerId: current.customerId,
      );
      _demoChanges.add(_demoSession);
      return _demoSession!;
    }

    final c = _client;
    if (c == null) {
      throw StateError('Supabase belum diinisialisasi.');
    }
    final response = await c.auth.updateUser(
      UserAttributes(data: {'full_name': displayName}),
    );
    final user = response.user;
    if (user == null) {
      throw StateError('Supabase tidak mengembalikan profil yang diperbarui.');
    }
    return _sessionForUser(user);
  }

  @override
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  }) async {
    if (_isDemoActive) {
      final current = _demoSession!;
      await customers.linkCustomer(
        uid: current.uid,
        customerId: customerId,
        verifiedPhone: normalizePhone(verification.phoneNumber),
      );
      _demoSession = AuthSessionUser(
        uid: current.uid,
        email: current.email,
        displayName: current.displayName,
        photoUrl: current.photoUrl,
        customerId: customerId,
      );
      _demoChanges.add(_demoSession);
      return _demoSession!;
    }

    final c = _client;
    final currentUser = c?.auth.currentUser;
    if (currentUser == null) {
      throw const CustomerLinkException('Sesi login berakhir.');
    }

    await customers.linkCustomer(
      uid: currentUser.id,
      customerId: customerId,
      verifiedPhone: normalizePhone(verification.phoneNumber),
    );

    return _sessionForUser(currentUser);
  }

  @override
  Future<AuthSessionUser?> refreshCurrentUser() async {
    if (_isDemoActive) {
      final current = _demoSession;
      if (current == null) return null;
      final customerId = await customers.linkedCustomerId(current.uid);
      _demoSession = AuthSessionUser(
        uid: current.uid,
        email: current.email,
        displayName: current.displayName,
        photoUrl: current.photoUrl,
        customerId: customerId,
      );
      // Emit perubahan agar router dan listener lain menerima update
      _demoChanges.add(_demoSession);
      return _demoSession;
    }
    final c = _client;
    if (c == null) return null;
    final user = c.auth.currentUser;
    if (user == null) return null;
    return _sessionForUser(user);
  }

  Future<AuthSessionUser> _sessionForUser(User user) async {
    final customerId = await customers.linkedCustomerId(user.id);
    return AuthSessionUser.fromSupabaseUser(user, customerId: customerId);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  final customers = ref.watch(customerRepositoryProvider);

  if (!config.isConfigured) {
    return MockAuthRepository(customers);
  }

  if (config.isTestingMode) {
    return TestingSupabaseAuthRepository(customers: customers);
  }

  return SupabaseAuthRepository(customers: customers);
});
