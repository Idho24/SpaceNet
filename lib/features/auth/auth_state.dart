import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/otp_repository.dart';

enum AuthStatus { loading, unauthenticated, authenticated, error }

class AuthState {
  final AuthStatus status;
  final AuthSessionUser? user;
  final String? errorMessage;

  const AuthState._(this.status, this.user, this.errorMessage);

  const AuthState.loading() : this._(AuthStatus.loading, null, null);
  const AuthState.unauthenticated() : this._(AuthStatus.unauthenticated, null, null);
  const AuthState.authenticated(AuthSessionUser user)
      : this._(AuthStatus.authenticated, user, null);
  const AuthState.error(String message)
      : this._(AuthStatus.error, null, message);

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  late final StreamSubscription<AuthSessionUser?> _subscription;

  AuthNotifier(this._repository)
      : super(
          _repository.isDemo
              ? const AuthState.unauthenticated()
              : const AuthState.loading(),
        ) {
    _subscription = _repository.authStateChanges.listen(
      (user) {
        state = user == null
            ? const AuthState.unauthenticated()
            : AuthState.authenticated(user);
      },
      onError: (Object error, StackTrace stackTrace) {
        state = AuthState.error(_userFacingError(error));
      },
    );
  }

  Future<void> signInWithGoogle() async {
    state = const AuthState.loading();
    try {
      final user = await _repository.signInWithGoogle();
      state = AuthState.authenticated(user);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        state = const AuthState.unauthenticated();
        return;
      }
      state = AuthState.error(_userFacingError(error));
    } on firebase_auth.FirebaseAuthException catch (error) {
      state = AuthState.error(_userFacingError(error));
    } on StateError catch (error) {
      state = AuthState.error(_userFacingError(error));
    } on Exception catch (error) {
      state = AuthState.error(_userFacingError(error));
    }
  }

  Future<void> signInDemo() async {
    state = const AuthState.loading();
    try {
      final user = await _repository.signInDemo();
      state = AuthState.authenticated(user);
    } on Exception catch (error) {
      state = AuthState.error(_userFacingError(error));
    }
  }

  Future<void> signOut() async {
    state = const AuthState.loading();
    try {
      await _repository.signOut();
      state = const AuthState.unauthenticated();
    } on Exception catch (error) {
      state = AuthState.error(_userFacingError(error));
    }
  }

  Future<void> refreshCurrentUser() async {
    try {
      final user = await _repository.refreshCurrentUser();
      state = user == null
          ? const AuthState.unauthenticated()
          : AuthState.authenticated(user);
    } on Exception catch (error) {
      state = AuthState.error(_userFacingError(error));
    }
  }

  Future<AuthSessionUser> linkCustomer({
    required String customerId,
    required PhoneVerification verification,
  }) {
    return _repository.linkCustomer(
      customerId: customerId,
      verification: verification,
    );
  }

  static String _userFacingError(Object error) {
    if (error is firebase_auth.FirebaseAuthException) {
      return switch (error.code) {
        'network-request-failed' =>
          'Tidak ada koneksi. Periksa jaringan lalu coba lagi.',
        'account-exists-with-different-credential' =>
          'Email ini sudah terhubung dengan metode login lain.',
        'credential-already-in-use' =>
          'Nomor atau akun tersebut sudah digunakan akun lain.',
        'provider-already-linked' => 'Nomor ponsel sudah terhubung ke akun ini.',
        'invalid-verification-code' => 'Kode OTP salah atau sudah kedaluwarsa.',
        'too-many-requests' => 'Terlalu banyak percobaan. Coba kembali nanti.',
        _ => 'Login atau verifikasi gagal. Silakan coba kembali.',
      };
    }
    if (error is GoogleSignInException) {
      return 'Google Sign-In gagal (${error.code.name}). Periksa konfigurasi OAuth.';
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

final currentUserProvider = StreamProvider<AuthSessionUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
