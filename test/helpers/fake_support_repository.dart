import 'dart:typed_data';

import 'package:spacenet/data/models/support_ticket.dart';
import 'package:spacenet/data/repositories/support_repository.dart';

class FakeSupportRepository implements SupportRepository {
  final Map<String, SupportDetail> reports = {};
  int reads = 0;
  bool failCreate = false;
  bool admin = false;
  @override
  Future<bool> isAdmin() async => admin;
  @override
  Future<List<SupportTicket>> loadTickets() async {
    reads++;
    return reports.values.map((d) => d.ticket).toList();
  }

  @override
  Future<SupportDetail?> loadDetail(String id) async => reports[id];
  @override
  Future<String> create({
    required String id,
    required String category,
    required String description,
    Uint8List? photo,
  }) async {
    if (failCreate) throw StateError('Koneksi terputus. Coba kirim lagi.');
    reports.putIfAbsent(
      id,
      () => SupportDetail(
        SupportTicket(
          id: id,
          customerId: '0012995',
          customerName: 'Pelanggan pengujian',
          category: category,
          description: description,
          status: 'open',
          number: 2043,
          version: 1,
          createdAt: DateTime.utc(2026, 11, 18),
          updatedAt: DateTime.utc(2026, 11, 18),
        ),
        [
          SupportEvent(
            actorRole: 'customer',
            status: 'open',
            message: 'Laporan diterima.',
            createdAt: DateTime.utc(2026, 11, 18),
          ),
        ],
        null,
      ),
    );
    return id;
  }

  @override
  Future<void> update(
    SupportTicket ticket,
    String status,
    String message,
  ) async {
    final previous = reports[ticket.id]!;
    if (previous.ticket.version != ticket.version) {
      throw StateError('Muat ulang laporan.');
    }
    reports[ticket.id] = SupportDetail(
      SupportTicket(
        id: ticket.id,
        customerId: ticket.customerId,
        customerName: ticket.customerName,
        category: ticket.category,
        description: ticket.description,
        status: status,
        number: ticket.number,
        version: ticket.version + 1,
        createdAt: ticket.createdAt,
        updatedAt: DateTime.utc(2026, 11, 18, 1),
      ),
      [
        ...previous.events,
        SupportEvent(
          actorRole: admin ? 'admin' : 'customer',
          status: status,
          message: message,
          createdAt: DateTime.utc(2026, 11, 18, 1),
        ),
      ],
      null,
    );
  }
}
