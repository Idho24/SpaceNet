import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:spacenet/data/repositories/midtrans_payment_repository.dart';

void main() {
  test('shows the Edge Function error without leaking exception internals', () {
    final exception = MidtransPaymentException.fromFunctionException(
      const FunctionsHttpException(
        status: 502,
        details: {
          'error':
              'Midtrans menolak akses (HTTP 403). Periksa Server Key Sandbox.',
        },
      ),
    );

    expect(
      exception.message,
      'Midtrans menolak akses (HTTP 403). Periksa Server Key Sandbox.',
    );
    expect(exception.toString(), exception.message);
  });

  test('uses a safe fallback for malformed Edge Function errors', () {
    final exception = MidtransPaymentException.fromFunctionException(
      const FunctionsHttpException(status: 502, details: 'not-json'),
    );

    expect(exception.message, contains('HTTP 502'));
    expect(exception.message, isNot(contains('not-json')));
  });

  test('parses a sandbox payment response', () {
    final payment = MidtransPayment.fromMap({
      'orderId': 'SPN-test-order',
      'invoiceId': 'INV-2026-10-001',
      'redirectUrl': 'https://app.sandbox.midtrans.com/snap/v2/vtweb/test',
      'amount': 249000,
      'status': 'pending',
      'paymentType': 'bank_transfer',
      'transactionId': 'midtrans-transaction',
      'updatedAt': '2026-11-17T10:00:00.000Z',
      'statusMessage': 'Buka checkout dan pilih metode pembayaran.',
    });

    expect(payment.amount, 249000);
    expect(payment.status, MidtransPaymentStatus.pending);
    expect(payment.invoiceId, 'INV-2026-10-001');
    expect(payment.paymentType, 'bank_transfer');
    expect(payment.transactionId, 'midtrans-transaction');
    expect(payment.updatedAt, DateTime.utc(2026, 11, 17, 10));
    expect(payment.statusMessage, 'Buka checkout dan pilih metode pembayaran.');
  });

  test('rejects a checkout URL outside the Midtrans Sandbox domain', () {
    expect(
      () => MidtransPayment.fromMap({
        'orderId': 'SPN-test-order',
        'invoiceId': 'INV-2026-10-001',
        'redirectUrl': 'https://example.com/checkout',
        'amount': 249000,
        'status': 'pending',
      }),
      throwsFormatException,
    );
  });
}
