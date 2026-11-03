import 'package:flutter_riverpod/flutter_riverpod.dart';

enum InvoiceStatus { unpaid, paid, expired }

class MockInvoice {
  final String id;
  final String period;
  final int amount;
  final DateTime dueDate;
  final InvoiceStatus status;

  const MockInvoice({
    required this.id,
    required this.period,
    required this.amount,
    required this.dueDate,
    required this.status,
  });
}

class MockTicket {
  final String id;
  final String category;
  final String status;
  final String date;
  final String description;

  const MockTicket({
    required this.id,
    required this.category,
    required this.status,
    required this.date,
    required this.description,
  });
}

class MockTransaction {
  final String id;
  final String invoiceId;
  final String date;
  final String method;
  final int amount;
  final String status;

  const MockTransaction({
    required this.id,
    required this.invoiceId,
    required this.date,
    required this.method,
    required this.amount,
    required this.status,
  });
}

class MockRepository {
  final List<MockInvoice> _invoices = [
    MockInvoice(
      id: 'INV-2026-10-001',
      period: 'Oktober 2026',
      amount: 249000,
      dueDate: DateTime(2026, 11, 14),
      status: InvoiceStatus.unpaid,
    ),
    MockInvoice(
      id: 'INV-2026-09-001',
      period: 'September 2026',
      amount: 249000,
      dueDate: DateTime(2026, 10, 14),
      status: InvoiceStatus.paid,
    ),
    MockInvoice(
      id: 'INV-2026-08-001',
      period: 'Agustus 2026',
      amount: 249000,
      dueDate: DateTime(2026, 9, 14),
      status: InvoiceStatus.paid,
    ),
  ];

  final List<MockTicket> _tickets = [
    const MockTicket(
      id: 'SPN-2042',
      category: 'Internet lambat',
      status: 'Teknisi dijadwalkan',
      date: '12 Okt 2026',
      description: 'Koneksi melambat setiap malam sejak pukul 20.00.',
    ),
  ];

  final List<MockTransaction> transactions = const [
    MockTransaction(
      id: 'TRX-009182',
      invoiceId: 'INV-2026-09-001',
      date: '14 Sep 2026, 09.18',
      method: 'QRIS',
      amount: 249000,
      status: 'Berhasil',
    ),
    MockTransaction(
      id: 'TRX-008201',
      invoiceId: 'INV-2026-08-001',
      date: '14 Agu 2026, 11.42',
      method: 'Virtual Account BCA',
      amount: 249000,
      status: 'Berhasil',
    ),
  ];

  List<MockInvoice> get invoices => List.unmodifiable(_invoices);
  List<MockTicket> get tickets => List.unmodifiable(_tickets);
  MockInvoice? get currentInvoice => _invoices
      .where((invoice) => invoice.status == InvoiceStatus.unpaid)
      .firstOrNull;

  Future<List<MockInvoice>> loadInvoices() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return invoices;
  }

  Future<List<MockTicket>> loadTickets() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return tickets;
  }

  MockTicket createTicket({
    required String category,
    required String description,
  }) {
    final ticket = MockTicket(
      id: 'SPN-${2042 + _tickets.length}',
      category: category,
      status: 'Menunggu',
      date: 'Baru saja',
      description: description,
    );
    _tickets.insert(0, ticket);
    return ticket;
  }

  MockInvoice? invoiceById(String id) {
    for (final invoice in _invoices) {
      if (invoice.id == id) return invoice;
    }
    return null;
  }

  MockTicket? ticketById(String id) {
    for (final ticket in _tickets) {
      if (ticket.id == id) return ticket;
    }
    return null;
  }

  MockTicket? updateTicketStatus(String id, String status) {
    final index = _tickets.indexWhere((ticket) => ticket.id == id);
    if (index < 0) return null;
    final old = _tickets[index];
    final updated = MockTicket(
      id: old.id,
      category: old.category,
      status: status,
      date: old.date,
      description: old.description,
    );
    _tickets[index] = updated;
    return updated;
  }

  MockTransaction? transactionById(String id) {
    for (final transaction in transactions) {
      if (transaction.id == id) return transaction;
    }
    return null;
  }
}

final mockRepositoryProvider = Provider<MockRepository>((ref) {
  return MockRepository();
});
