import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spacenet/core/routing/payment_return.dart';
import 'package:spacenet/data/models/customer_model.dart';
import 'package:spacenet/data/models/payment_transaction.dart';
import 'package:spacenet/data/repositories/customer_repository.dart';
import 'package:spacenet/data/repositories/invoice_repository.dart';
import 'package:spacenet/data/repositories/midtrans_payment_repository.dart';
import 'package:spacenet/data/repositories/payment_history_repository.dart';
import 'package:spacenet/features/home/home_screen.dart';
import 'package:spacenet/features/screens/detail_screens.dart';

class PaidRepository implements MidtransPaymentRepository {
  @override
  bool get hasAuthenticatedSession => true;
  @override
  Future<MidtransPayment> createPayment(String invoiceId) => refreshStatus('SPN-paid');
  @override
  Future<MidtransPayment> refreshStatus(String orderId) async => MidtransPayment(
    orderId: orderId, invoiceId: 'INV-paid', amount: 170000,
    redirectUrl: 'https://app.sandbox.midtrans.com/snap/v2/vtweb/test',
    status: MidtransPaymentStatus.paid, paymentType: 'dana',
  );
}

void main() {
  test('callback order is read from outer query or Flutter hash route', () {
    expect(paymentOrderFromUri(Uri.parse('http://localhost:3000/?order_id=SPN-one#/home')), 'SPN-one');
    expect(paymentOrderFromUri(Uri.parse('http://localhost:3000/#/payment-result?order_id=SPN-two')), 'SPN-two');
    expect(paymentOrderFromUri(Uri.parse('http://localhost:3000/#/home')), isNull);
  });

  test('history parses the verified payment timestamp and amount', () {
    final transaction = PaymentTransaction.fromMap({
      'order_id': 'SPN-paid', 'invoice_id': 'INV-paid', 'amount': 170000,
      'paid_at': '2026-11-18T02:58:53Z', 'payment_type': 'dana',
    });
    expect(transaction.date, '18 Nov 2026');
    expect(transaction.method, 'DANA');
    expect(transaction.status, 'Lunas');
    expect(() => PaymentTransaction.fromMap({
      'order_id': 'SPN-paid', 'invoice_id': 'INV-paid', 'amount': -1,
      'paid_at': '2026-11-18T02:58:53Z',
    }), throwsFormatException);
  });

  testWidgets('verified completion returns to billing and refreshes payment data', (tester) async {
    final router = GoRouter(initialLocation: '/payment-result', routes: [
      GoRoute(path: '/payment-result', builder: (_, _) => const PaymentResultScreen(orderId: 'SPN-paid')),
      GoRoute(path: '/billing', builder: (_, _) => const Scaffold(body: Text('Menu pembayaran'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      midtransPaymentRepositoryProvider.overrideWithValue(PaidRepository()),
      invoicesProvider.overrideWith((ref) async => []),
      activeCustomerProvider.overrideWith((ref) async => null),
      paymentHistoryProvider.overrideWith((ref) async => []),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/billing');
    expect(find.text('Menu pembayaran'), findsOneWidget);
  });

  testWidgets('history renders paid records and supports their receipt', (tester) async {
    final transaction = PaymentTransaction(id: 'SPN-real', invoiceId: 'INV-real',
      amount: 170000, method: 'DANA', paidAt: DateTime.utc(2026, 11, 18));
    final router = GoRouter(initialLocation: '/transactions', routes: [
      GoRoute(path: '/transactions', builder: (_, _) => const TransactionsScreen()),
      GoRoute(path: '/transactions/:id', builder: (_, state) =>
        TransactionDetailScreen(transactionId: state.pathParameters['id']!)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      paymentHistoryProvider.overrideWith((ref) async => [transaction]),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('INV-real'), findsOneWidget);
    expect(find.text('Lunas'), findsOneWidget);
    await tester.tap(find.text('INV-real'));
    await tester.pumpAndSettle();
    expect(find.text('SPN-real'), findsOneWidget);
    expect(find.text('DANA'), findsOneWidget);
  });

  testWidgets('active package uses the renewed expiry from customer data', (tester) async {
    final customer = CustomerModel(
      customerId: '0013010', name: 'Pelanggan', phone: '0800',
      email: 'test@example.com', address: 'Samarinda',
      activePackage: 'Paket Home 20Mbps', subscriptionStatus: 'active',
      installationDate: DateTime.utc(2026, 1, 1),
      expiryDate: DateTime.utc(2026, 12, 18),
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026, 11, 18),
      monthlyFee: 170000,
    );
    await tester.pumpWidget(ProviderScope(overrides: [
      activeCustomerProvider.overrideWith((ref) async => customer),
      invoicesProvider.overrideWith((ref) async => []),
    ], child: const MaterialApp(home: Scaffold(body: SubscriptionTab()))));
    await tester.pumpAndSettle();
    expect(find.text('18 Des 2026'), findsOneWidget);
    expect(find.textContaining('30 Nov 2026'), findsNothing);
    expect(find.textContaining('200 Mbps'), findsNothing);
  });
}
