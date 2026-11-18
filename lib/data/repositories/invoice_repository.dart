import '../../features/auth/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';
import '../mock/mock_repository.dart';
import '../models/invoice_model.dart';

abstract interface class InvoiceRepository {
  Future<List<InvoiceModel>> loadInvoices();
}

class SupabaseInvoiceRepository implements InvoiceRepository {
  final SupabaseClient _client;

  const SupabaseInvoiceRepository(this._client);

  @override
  Future<List<InvoiceModel>> loadInvoices() async {
    final rows = await _client
        .from('invoices')
        .select('id, period, amount, due_at, status')
        .order('due_at', ascending: false);
    return rows
        .map((row) => InvoiceModel.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}

class PreviewInvoiceRepository implements InvoiceRepository {
  final MockRepository _mockRepository;

  const PreviewInvoiceRepository(this._mockRepository);

  @override
  Future<List<InvoiceModel>> loadInvoices() {
    return _mockRepository.loadInvoices();
  }
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (config.isConfigured) {
    return SupabaseInvoiceRepository(Supabase.instance.client);
  }
  return PreviewInvoiceRepository(ref.watch(mockRepositoryProvider));
});

final invoicesProvider = FutureProvider<List<InvoiceModel>>((ref) {
  ref.watch(authNotifierProvider.select((state) => state.user?.uid));
  return ref.watch(invoiceRepositoryProvider).loadInvoices();
});
