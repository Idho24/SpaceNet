import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';
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

class SupabaseCustomerRepository implements CustomerRepository {
  final SupabaseClient _client;

  SupabaseCustomerRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<String?> linkedCustomerId(String uid) async {
    final response = await _client
        .from('profiles')
        .select('customer_id')
        .eq('id', uid)
        .maybeSingle();

    final value = response?['customer_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    final response = await _client
        .from('customers')
        .select()
        .eq('customer_id', customerId)
        .maybeSingle();

    if (response == null) return null;
    return CustomerModel.fromMap(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> linkCustomer({
    required String uid,
    required String customerId,
    required String verifiedPhone,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || user.id != uid) {
      throw const CustomerLinkException(
        'Sesi login tidak valid. Silakan masuk kembali.',
      );
    }
    if (user.phoneConfirmedAt == null ||
        user.phone == null ||
        normalizePhone(user.phone!) != normalizePhone(verifiedPhone)) {
      throw const CustomerLinkException(
        'Nomor ponsel belum terverifikasi pada akun Supabase.',
      );
    }

    try {
      await _client.rpc('link_customer', params: {'p_customer_id': customerId});
    } on PostgrestException catch (error) {
      throw CustomerLinkException(error.message);
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
  Future<String?> linkedCustomerId(String uid) async => _linkedCustomers[uid];

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
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (config.isConfigured) {
    return SupabaseCustomerRepository();
  }
  return MockCustomerRepository();
});

final customerProfileProvider = FutureProvider.family<CustomerModel?, String>((
  ref,
  customerId,
) {
  return ref.watch(customerRepositoryProvider).getCustomer(customerId);
});
