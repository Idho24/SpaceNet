import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_runtime_config.dart';
import '../models/customer_model.dart';

class CustomerLinkException implements Exception {
  final String message;

  const CustomerLinkException(this.message);

  @override
  String toString() => message;
}

abstract interface class CustomerRepository {
  Future<String?> linkedCustomerId(String uid);
  Future<CustomerModel?> getCustomer(String customerId);
  Future<void> linkCustomer({
    required String uid,
    required String customerId,
    required String verifiedPhone,
  });
}

class FirestoreCustomerRepository implements CustomerRepository {
  final FirebaseFirestore _firestore;

  FirestoreCustomerRepository(this._firestore);

  @override
  Future<String?> linkedCustomerId(String uid) async {
    final document = await _firestore.collection('users').doc(uid).get();
    final value = document.data()?['customer_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    final document =
        await _firestore.collection('customers').doc(customerId).get();
    final data = document.data();
    if (!document.exists || data == null) return null;
    return CustomerModel.fromFirestore(document.id, data);
  }

  @override
  Future<void> linkCustomer({
    required String uid,
    required String customerId,
    required String verifiedPhone,
  }) async {
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizePhone(verifiedPhone))) {
      throw const CustomerLinkException(
        'Nomor ponsel terverifikasi tidak valid.',
      );
    }
    final customerRef = _firestore.collection('customers').doc(customerId);
    final userRef = _firestore.collection('users').doc(uid);
    final batch = _firestore.batch();
    batch.update(customerRef, {'linked_uid': uid});
    batch.update(userRef, {
      'customer_id': customerId,
      'phone_verified': true,
      'updated_at': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'not-found' ||
          error.code == 'failed-precondition') {
        throw const CustomerLinkException(
          'Data pelanggan tidak dapat dihubungkan. Pastikan ID dan nomor '
          'terverifikasi sesuai data SpaceNet, dan akun belum terhubung.',
        );
      }
      rethrow;
    }
  }
}

class MockCustomerRepository implements CustomerRepository {
  static final _customer = CustomerModel(
    customerId: '0012995',
    name: 'Nabila Sari',
    phone: '+6281255671201',
    email: 'customer@spacenet.id',
    address: 'Jl. Cikutra No. 22, Bandung',
    activePackage: 'Home Fiber 200 Mbps',
    subscriptionStatus: 'active',
    installationDate: DateTime(2025, 6, 15),
    expiryDate: DateTime(2026, 11, 30),
    createdAt: DateTime(2025, 6, 1),
    updatedAt: DateTime(2026, 11, 1),
  );
  final Map<String, String> _linkedCustomers = {};

  @override
  Future<String?> linkedCustomerId(String uid) async =>
      _linkedCustomers[uid];

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    if (_linkedCustomers.containsValue(customerId) &&
        customerId == _customer.customerId) {
      return _customer;
    }
    return null;
  }

  @override
  Future<void> linkCustomer({
    required String uid,
    required String customerId,
    required String verifiedPhone,
  }) async {
    if (customerId != _customer.customerId ||
        normalizePhone(verifiedPhone) != normalizePhone(_customer.phone)) {
      throw const CustomerLinkException(
        'Data tidak dapat diverifikasi. Periksa kembali ID dan nomor ponsel.',
      );
    }
    final alreadyLinked = _linkedCustomers.entries.any(
      (entry) => entry.key != uid && entry.value == customerId,
    );
    if (alreadyLinked) {
      throw const CustomerLinkException(
        'Akun ini tidak dapat dihubungkan. Hubungi dukungan SpaceNet.',
      );
    }
    _linkedCustomers[uid] = customerId;
  }
}

String normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('0')) return '+62${digits.substring(1)}';
  return '+$digits';
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final config = ref.watch(firebaseRuntimeConfigProvider);
  if (config.isConfigured) {
    return FirestoreCustomerRepository(FirebaseFirestore.instance);
  }
  return MockCustomerRepository();
});

final customerProfileProvider =
    FutureProvider.family<CustomerModel?, String>((ref, customerId) {
  return ref.watch(customerRepositoryProvider).getCustomer(customerId);
});
