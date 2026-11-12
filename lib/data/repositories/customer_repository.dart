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

SupabaseClient? _safeSupabaseClient() {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

class SupabaseCustomerRepository implements CustomerRepository {
  final SupabaseClient? _client;

  SupabaseCustomerRepository({SupabaseClient? client})
    : _client = client ?? _safeSupabaseClient();

  SupabaseClient get client =>
      _client ??
      (throw const CustomerLinkException('Supabase belum diinisialisasi.'));

  @override
  Future<String?> linkedCustomerId(String uid) async {
    final c = _client;
    if (c == null) return null;
    final response = await c
        .from('profiles')
        .select('customer_id')
        .eq('id', uid)
        .maybeSingle();

    final value = response?['customer_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    final c = _client;
    if (c == null) return null;
    final response = await c
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
    final c = client;
    final user = c.auth.currentUser;
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
      await c.rpc('link_customer', params: {'p_customer_id': customerId});
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
  if (config.isConfigured && config.isTestingMode) {
    return TestingSupabaseCustomerRepository();
  }
  if (config.isConfigured) {
    return SupabaseCustomerRepository();
  }
  return MockCustomerRepository();
});

/// Repository khusus mode pengujian: data customer diambil dari Supabase,
/// tetapi linkCustomer menerima verifikasi OTP lokal (mock) tanpa
/// memeriksa phoneConfirmedAt di Supabase Auth.
class TestingSupabaseCustomerRepository implements CustomerRepository {
  final SupabaseClient? _client;
  final Map<String, String> _localLinkedCustomers = {};
  // Cache customer data yang berhasil diambil dari Supabase
  final Map<String, CustomerModel> _customerCache = {};

  TestingSupabaseCustomerRepository({SupabaseClient? client})
    : _client = client ?? _safeSupabaseClient();

  @override
  Future<String?> linkedCustomerId(String uid) async {
    // Cek memori lokal terlebih dahulu (untuk mode demo lokal)
    if (_localLinkedCustomers.containsKey(uid)) {
      return _localLinkedCustomers[uid];
    }

    final c = _client;
    if (c == null) return null;

    final user = c.auth.currentUser;
    if (user != null && user.id == uid) {
      try {
        final response = await c
            .from('profiles')
            .select('customer_id')
            .eq('id', uid)
            .maybeSingle();

        final value = response?['customer_id'];
        return value is String && value.isNotEmpty ? value : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    // Cek cache terlebih dahulu
    if (_customerCache.containsKey(customerId)) {
      return _customerCache[customerId];
    }

    final c = _client;
    if (c != null) {
      try {
        // Gunakan RPC yang bypass RLS untuk mode pengujian
        final response = await c.rpc('get_customer_for_testing', params: {
          'p_customer_id': customerId,
        });

        if (response != null) {
          final customer = CustomerModel.fromMap(Map<String, dynamic>.from(
            response is Map ? response : {},
          ));
          _customerCache[customerId] = customer;
          return customer;
        }
      } on PostgrestException catch (e) {
        // Jika RPC belum ada, coba query langsung (mungkin gagal karena RLS)
        if (e.message.contains('function') &&
            e.message.contains('does not exist')) {
          try {
            final directResponse = await c
                .from('customers')
                .select()
                .eq('customer_id', customerId)
                .maybeSingle();

            if (directResponse != null) {
              final customer = CustomerModel.fromMap(
                Map<String, dynamic>.from(directResponse),
              );
              _customerCache[customerId] = customer;
              return customer;
            }
          } catch (_) {
            // RLS blocked or other error — fallback to mock
          }
        }
        // Other PostgrestException — fallback to mock
      } catch (_) {
        // Fallback ke mock jika query Supabase gagal
      }
    }

    // Jika di database Supabase tidak ditemukan atau error, gunakan mock customer
    if (customerId == '0012995') {
      final mock = CustomerModel(
        customerId: '0012995',
        name: 'Nabila Sari',
        phone: '+628****1201',
        email: 'customer@spacenet.id',
        address: 'Jl. Cikutra No. 22, Bandung',
        activePackage: 'Home Fiber 200 Mbps',
        subscriptionStatus: 'active',
        installationDate: DateTime(2025, 6, 15),
        expiryDate: DateTime(2026, 11, 30),
        createdAt: DateTime(2025, 6, 1),
        updatedAt: DateTime(2026, 11, 1),
      );
      _customerCache[customerId] = mock;
      return mock;
    }
    return null;
  }

  @override
  Future<void> linkCustomer({
    required String uid,
    required String customerId,
    required String verifiedPhone,
  }) async {
    // Validasi: pastikan customer ada di database sebelum linking
    final customer = await getCustomer(customerId);
    if (customer == null) {
      throw const CustomerLinkException(
        'ID pelanggan tidak ditemukan. Periksa kembali data yang dimasukkan.',
      );
    }

    final c = _client;
    if (c != null) {
      final user = c.auth.currentUser;
      if (user != null && user.id == uid) {
        try {
          await c.rpc(
            'link_customer_testing',
            params: {'p_customer_id': customerId},
          );
          return;
        } on PostgrestException catch (error) {
          // Jika RPC belum ada di database, simpan secara lokal agar pengujian tetap jalan
          if (error.message.contains('function') &&
              error.message.contains('does not exist')) {
            _localLinkedCustomers[uid] = customerId;
            return;
          }
          throw CustomerLinkException(error.message);
        } catch (error) {
          throw CustomerLinkException(error.toString());
        }
      }
    }

    // Untuk demo user tanpa auth Supabase atau client uninitialized, simpan lokal
    _localLinkedCustomers[uid] = customerId;
  }
}

final customerProfileProvider = FutureProvider.family<CustomerModel?, String>((
  ref,
  customerId,
) {
  return ref.watch(customerRepositoryProvider).getCustomer(customerId);
});
