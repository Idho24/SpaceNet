import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_runtime_config.dart';
import '../../features/auth/auth_state.dart';
import '../models/payment_transaction.dart';

abstract interface class PaymentHistoryRepository {
  Future<List<PaymentTransaction>> loadTransactions();
}

class SupabasePaymentHistoryRepository implements PaymentHistoryRepository {
  final SupabaseClient client;
  const SupabasePaymentHistoryRepository(this.client);

  @override
  Future<List<PaymentTransaction>> loadTransactions() async {
    final rows = await client.rpc('get_my_payment_history') as List;
    return rows.map((row) => PaymentTransaction.fromMap(
      Map<String, dynamic>.from(row as Map),
    )).toList(growable: false);
  }
}

final paymentHistoryRepositoryProvider = Provider<PaymentHistoryRepository?>((ref) {
  if (!ref.watch(supabaseRuntimeConfigProvider).isConfigured) return null;
  return SupabasePaymentHistoryRepository(Supabase.instance.client);
});

final paymentHistoryProvider = FutureProvider<List<PaymentTransaction>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null || !user.isCustomerLinked) return const [];
  final repository = ref.watch(paymentHistoryRepositoryProvider);
  if (repository == null) return const [];
  return repository.loadTransactions();
});
