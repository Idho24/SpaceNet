import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/firebase/firebase_runtime_config.dart';
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
  Future<AuthSessionUser> signInWithGoogle();
  Future<AuthSessionUser> signInDemo();
  Future<void> signOut();
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  });
  Future<AuthSessionUser?> refreshCurrentUser();
}

class FirebaseAuthRepository implements AuthRepository {
  final firebase_auth.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;
  final FirebaseRuntimeConfig _config;
  final CustomerRepository _customers;
  Future<void>? _googleInitialization;

  factory FirebaseAuthRepository({
    required firebase_auth.FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseRuntimeConfig config,
    required CustomerRepository customers,
  }) {
    return FirebaseAuthRepository._(
      auth: auth,
      firestore: firestore,
      config: config,
      customers: customers,
    );
  }

  FirebaseAuthRepository._({
    required this._auth,
    required this._firestore,
    required this._config,
    required this._customers,
  }) : _googleSignIn = GoogleSignIn.instance;

  @override
  bool get isDemo => false;

  @override
  AuthSessionUser? get currentSession {
    final user = _auth.currentUser;
    if (user == null) return null;
    return AuthSessionUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      customerId: null,
    );
  }

  @override
  Stream<AuthSessionUser?> get authStateChanges async* {
    await for (final user in _auth.userChanges()) {
      if (user == null) {
        yield null;
      } else {
        yield await _loadSession(user);
      }
    }
  }

  Future<void> _initializeGoogleSignIn() {
    return _googleInitialization ??= _googleSignIn.initialize(
      clientId: kIsWeb && _config.googleWebClientId.isNotEmpty
          ? _config.googleWebClientId
          : null,
      serverClientId: _config.googleWebClientId.isNotEmpty
          ? _config.googleWebClientId
          : null,
    );
  }

  @override
  Future<AuthSessionUser> signInWithGoogle() async {
    await _initializeGoogleSignIn();
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw firebase_auth.FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google Sign-In tidak mengembalikan token identitas.',
      );
    }

    final credential = firebase_auth.GoogleAuthProvider.credential(
      idToken: idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) {
      throw firebase_auth.FirebaseAuthException(
        code: 'missing-auth-user',
        message: 'Firebase Authentication tidak mengembalikan pengguna.',
      );
    }
    await _ensureUserDocument(user);
    return _loadSession(user);
  }

  Future<void> _ensureUserDocument(firebase_auth.User user) async {
    final reference = _firestore.collection('users').doc(user.uid);
    final snapshot = await reference.get();
    if (snapshot.exists) return;
    await reference.set({
      'uid': user.uid,
      'email': user.email,
      'display_name': user.displayName,
      'photo_url': user.photoURL,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<AuthSessionUser> _loadSession(firebase_auth.User user) async {
    final customerId = await _customers.linkedCustomerId(user.uid);
    return AuthSessionUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      customerId: customerId,
    );
  }

  @override
  Future<AuthSessionUser> signInDemo() {
    throw UnsupportedError('Akun demo hanya tersedia tanpa Firebase.');
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  @override
  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  }) async {
    if (verification.localMock || verification.credential == null) {
      throw const CustomerLinkException(
        'Verifikasi lokal tidak dapat mengubah akun Firebase.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const CustomerLinkException('Sesi login berakhir. Silakan masuk kembali.');
    }

    final normalizedPhone = normalizePhone(verification.phoneNumber);
    var verifiedUser = user;
    if (user.phoneNumber == null) {
      final result = await user.linkWithCredential(verification.credential!);
      verifiedUser = result.user ?? _auth.currentUser ?? user;
    } else if (normalizePhone(user.phoneNumber!) != normalizedPhone) {
      throw const CustomerLinkException(
        'Nomor terverifikasi tidak cocok dengan sesi akun ini.',
      );
    }
    final linkedPhone = verifiedUser.phoneNumber;
    if (linkedPhone == null || normalizePhone(linkedPhone) != normalizedPhone) {
      throw const CustomerLinkException(
        'Nomor ponsel belum terverifikasi pada akun ini. Silakan coba kembali.',
      );
    }
    await verifiedUser.getIdToken(true);
    await _customers.linkCustomer(
      uid: verifiedUser.uid,
      customerId: customerId,
      verifiedPhone: linkedPhone,
    );
    return _loadSession(verifiedUser);
  }

  @override
  Future<AuthSessionUser?> refreshCurrentUser() async {
    final user = _auth.currentUser;
    return user == null ? null : _loadSession(user);
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
  Future<AuthSessionUser> signInWithGoogle() {
    throw UnsupportedError(
      'Konfigurasikan Firebase untuk menggunakan Google Sign-In.',
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
  final config = ref.watch(firebaseRuntimeConfigProvider);
  final customers = ref.watch(customerRepositoryProvider);
  if (config.isConfigured) {
    return FirebaseAuthRepository(
      auth: firebase_auth.FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      config: config,
      customers: customers,
    );
  }
  return MockAuthRepository(customers);
});
