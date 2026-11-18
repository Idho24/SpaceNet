enum InvoiceStatus { unpaid, paid, expired }

class InvoiceModel {
  final String id;
  final String period;
  final int amount;
  final DateTime dueDate;
  final InvoiceStatus status;

  const InvoiceModel({
    required this.id,
    required this.period,
    required this.amount,
    required this.dueDate,
    required this.status,
  });

  factory InvoiceModel.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final period = map['period'];
    final amount = map['amount'];
    final dueAt = map['due_at'];
    final rawStatus = map['status'];
    if (id is! String ||
        period is! String ||
        amount is! num ||
        amount <= 0 ||
        amount.toInt() != amount ||
        dueAt is! String ||
        rawStatus is! String) {
      throw const FormatException(
        'Data invoice tidak lengkap atau tidak valid.',
      );
    }

    final dueDate = DateTime.tryParse(dueAt);
    if (dueDate == null) {
      throw const FormatException('Tanggal jatuh tempo invoice tidak valid.');
    }

    final status = switch (rawStatus) {
      'unpaid' => InvoiceStatus.unpaid,
      'paid' => InvoiceStatus.paid,
      'expired' => InvoiceStatus.expired,
      _ => throw FormatException('Status invoice tidak dikenal: $rawStatus'),
    };

    return InvoiceModel(
      id: id,
      period: period,
      amount: amount.toInt(),
      dueDate: dueDate,
      status: status,
    );
  }
}
