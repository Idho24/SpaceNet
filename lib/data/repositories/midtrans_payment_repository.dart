import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_runtime_config.dart';

enum MidtransPaymentStatus {
  pending('Menunggu pembayaran'),
  paid('Pembayaran berhasil'),
  failed('Pembayaran gagal'),
  expired('Pembayaran kedaluwarsa'),
  cancelled('Pembayaran dibatalkan');

  final String label;

  const MidtransPaymentStatus(this.label);

  static MidtransPaymentStatus fromValue(String value) {
    return switch (value) {
      'pending' => pending,
      'paid' => paid,
      'failed' => failed,
      'expired' => expired,
      'cancelled' => cancelled,
      _ => throw FormatException('Status pembayaran Midtrans tidak dikenal.'),
    };
  }
}

class MidtransPayment {
  final String orderId;
  final String invoiceId;
  final String redirectUrl;
  final int amount;
  final MidtransPaymentStatus status;
  final String? paymentType;
  final String? transactionId;
  final DateTime? updatedAt;
  final String? statusMessage;

  const MidtransPayment({
    required this.orderId,
    required this.invoiceId,
    required this.redirectUrl,
    required this.amount,
    required this.status,
    this.paymentType,
    this.transactionId,
    this.updatedAt,
    this.statusMessage,
  });

  factory MidtransPayment.fromMap(Map<String, dynamic> map) {
    final orderId = map['orderId'];
    final invoiceId = map['invoiceId'];
    final redirectUrl = map['redirectUrl'];
    final amount = map['amount'];
    final status = map['status'];
    final paymentType = map['paymentType'];
    final transactionId = map['transactionId'];
    final updatedAtValue = map['updatedAt'];
    if (orderId is! String ||
        invoiceId is! String ||
        redirectUrl is! String ||
        amount is! num ||
        amount <= 0 ||
        amount.toInt() != amount ||
        status is! String ||
        (paymentType != null && paymentType is! String) ||
        (transactionId != null && transactionId is! String)) {
      throw const FormatException('Respons pembayaran Midtrans tidak lengkap.');
    }

    DateTime? updatedAt;
    if (updatedAtValue != null) {
      if (updatedAtValue is! String) {
        throw const FormatException('Waktu transaksi Midtrans tidak valid.');
      }
      updatedAt = DateTime.tryParse(updatedAtValue);
      if (updatedAt == null) {
        throw const FormatException('Waktu transaksi Midtrans tidak valid.');
      }
    }

    final uri = Uri.tryParse(redirectUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'app.sandbox.midtrans.com') {
      throw const FormatException(
        'Tautan checkout Midtrans Sandbox tidak valid.',
      );
    }

    return MidtransPayment(
      orderId: orderId,
      invoiceId: invoiceId,
      redirectUrl: redirectUrl,
      amount: amount.toInt(),
      status: MidtransPaymentStatus.fromValue(status),
      paymentType: paymentType as String?,
      transactionId: transactionId as String?,
      updatedAt: updatedAt,
      statusMessage: map['statusMessage'] is String
          ? map['statusMessage'] as String
          : null,
    );
  }
}

abstract interface class MidtransPaymentRepository {
  bool get hasAuthenticatedSession;

  Future<MidtransPayment> createPayment(String invoiceId);

  Future<MidtransPayment> refreshStatus(String orderId);
}

class MidtransPaymentException implements Exception {
  final String message;

  const MidtransPaymentException(this.message);

  factory MidtransPaymentException.fromFunctionException(
    FunctionsHttpException exception,
  ) {
    final details = exception.details;
    if (details is Map && details['error'] is String) {
      return MidtransPaymentException(details['error'] as String);
    }

    return MidtransPaymentException(
      'Server pembayaran gagal (HTTP ${exception.status}). Coba lagi nanti.',
    );
  }

  @override
  String toString() => message;
}

class SupabaseMidtransPaymentRepository implements MidtransPaymentRepository {
  final SupabaseClient _client;

  const SupabaseMidtransPaymentRepository(this._client);

  @override
  bool get hasAuthenticatedSession => _client.auth.currentSession != null;

  @override
  Future<MidtransPayment> createPayment(String invoiceId) async {
    _requireAuthenticatedSession();
    return _invokePaymentFunction('create-midtrans-payment', {
      'invoiceId': invoiceId,
      if (kIsWeb)
        'returnUrl': Uri.base.replace(query: '', fragment: '').toString()
      else if (const String.fromEnvironment('PAYMENT_RETURN_URL') != '')
        'returnUrl': const String.fromEnvironment('PAYMENT_RETURN_URL'),
    });
  }

  @override
  Future<MidtransPayment> refreshStatus(String orderId) async {
    _requireAuthenticatedSession();
    return _invokePaymentFunction('get-midtrans-payment-status', {
      'orderId': orderId,
    });
  }

  Future<MidtransPayment> _invokePaymentFunction(
    String functionName,
    Map<String, String> body,
  ) async {
    try {
      final response = await _client.functions.invoke(functionName, body: body);
      return _parseResponse(response.data);
    } on FunctionsHttpException catch (error) {
      throw MidtransPaymentException.fromFunctionException(error);
    }
  }

  void _requireAuthenticatedSession() {
    if (!hasAuthenticatedSession) {
      throw StateError(
        'Masuk dengan akun Supabase yang sudah terhubung ke ID pelanggan '
        'untuk menggunakan pembayaran Sandbox.',
      );
    }
  }

  MidtransPayment _parseResponse(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Server tidak mengembalikan data pembayaran yang valid.',
      );
    }
    return MidtransPayment.fromMap(Map<String, dynamic>.from(value));
  }
}

final midtransPaymentRepositoryProvider = Provider<MidtransPaymentRepository?>((
  ref,
) {
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (!config.isConfigured) return null;
  return SupabaseMidtransPaymentRepository(Supabase.instance.client);
});
