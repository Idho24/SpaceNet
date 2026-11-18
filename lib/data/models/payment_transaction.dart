class PaymentTransaction {
  final String id;
  final String invoiceId;
  final int amount;
  final String method;
  final DateTime paidAt;
  final String? transactionId;

  const PaymentTransaction({
    required this.id, required this.invoiceId, required this.amount,
    required this.method, required this.paidAt, this.transactionId,
  });

  String get status => 'Lunas';
  String get date => formatPaymentDate(paidAt);

  factory PaymentTransaction.fromMap(Map<String, dynamic> map) {
    final amount = map['amount'];
    final paidAt = DateTime.tryParse(map['paid_at']?.toString() ?? '');
    if (map['order_id'] is! String || map['invoice_id'] is! String ||
        amount is! num || amount <= 0 || amount.toInt() != amount || paidAt == null) {
      throw const FormatException('Data riwayat pembayaran tidak valid.');
    }
    return PaymentTransaction(
      id: map['order_id'] as String, invoiceId: map['invoice_id'] as String,
      amount: amount.toInt(), paidAt: paidAt,
      method: (map['payment_type'] as String? ?? 'Midtrans').toUpperCase(),
      transactionId: map['transaction_id'] as String?,
    );
  }
}

String formatPaymentDate(DateTime date) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  final local = date.toUtc().add(const Duration(hours: 8));
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
