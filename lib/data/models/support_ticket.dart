import 'package:intl/intl.dart';

const supportStatuses = <String, String>{
  'open': 'Laporan diterima',
  'review': 'Sedang ditinjau',
  'in_progress': 'Dalam penanganan',
  'resolved': 'Selesai',
  'cancelled': 'Dibatalkan',
};

class SupportTicket {
  final String id, customerId, customerName, category, description, status;
  final String? photoPath;
  final int number, version;
  final DateTime createdAt, updatedAt;
  const SupportTicket({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.category,
    required this.description,
    required this.status,
    required this.number,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.photoPath,
  });

  factory SupportTicket.fromMap(Map<String, dynamic> row) => SupportTicket(
    id: row['id'] as String,
    customerId: row['customer_id'] as String,
    customerName: row['customer_name'] as String,
    category: row['category'] as String,
    description: row['description'] as String,
    status: row['status'] as String,
    number: (row['ticket_number'] as num).toInt(),
    version: (row['version'] as num).toInt(),
    photoPath: row['photo_path'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
  String get code => 'SPN-${number.toString().padLeft(6, '0')}';
  String get statusLabel => supportStatuses[status] ?? status;
  String get date => supportDate(createdAt);
  bool get isClosed => status == 'resolved' || status == 'cancelled';
}

String supportDate(DateTime date) =>
    DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());

class SupportEvent {
  final String actorRole, status, message;
  final DateTime createdAt;
  const SupportEvent({
    required this.actorRole,
    required this.status,
    required this.message,
    required this.createdAt,
  });
  factory SupportEvent.fromMap(Map<String, dynamic> row) => SupportEvent(
    actorRole: row['actor_role'] as String,
    status: row['status'] as String,
    message: row['message'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

class SupportDetail {
  final SupportTicket ticket;
  final List<SupportEvent> events;
  final String? photoUrl;
  const SupportDetail(this.ticket, this.events, this.photoUrl);
}
