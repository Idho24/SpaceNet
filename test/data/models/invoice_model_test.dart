import 'package:flutter_test/flutter_test.dart';
import 'package:spacenet/data/models/invoice_model.dart';

void main() {
  test('parses an owned Supabase invoice row', () {
    final invoice = InvoiceModel.fromMap({
      'id': 'INV-2026-10-001',
      'period': 'Oktober 2026',
      'amount': 249000,
      'due_at': '2026-11-14T00:00:00.000Z',
      'status': 'unpaid',
    });

    expect(invoice.id, 'INV-2026-10-001');
    expect(invoice.amount, 249000);
    expect(invoice.status, InvoiceStatus.unpaid);
    expect(invoice.dueDate, DateTime.parse('2026-11-14T00:00:00.000Z'));
  });

  test('rejects invalid invoice amounts and statuses', () {
    final row = {
      'id': 'INV-2026-10-001',
      'period': 'Oktober 2026',
      'amount': 249000,
      'due_at': '2026-11-14T00:00:00.000Z',
      'status': 'unpaid',
    };

    expect(
      () => InvoiceModel.fromMap({...row, 'amount': 249000.5}),
      throwsFormatException,
    );
    expect(
      () => InvoiceModel.fromMap({...row, 'status': 'unknown'}),
      throwsFormatException,
    );
  });
}
