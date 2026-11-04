class CustomerModel {
  final String customerId;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String activePackage;
  final String subscriptionStatus;
  final DateTime installationDate;
  final DateTime expiryDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerModel({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.activePackage,
    required this.subscriptionStatus,
    required this.installationDate,
    required this.expiryDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerModel.fromFirestore(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return CustomerModel.fromMap(data, documentId: documentId);
  }

  factory CustomerModel.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    return CustomerModel(
      customerId: _requiredString(data, 'customer_id', fallback: documentId),
      name: _requiredString(data, 'name'),
      phone: _requiredString(data, 'phone'),
      email: _requiredString(data, 'email'),
      address: _requiredString(data, 'address'),
      activePackage: _requiredString(data, 'active_package'),
      subscriptionStatus: _requiredString(data, 'subscription_status'),
      installationDate: _requiredDate(data, 'installation_date'),
      expiryDate: _requiredDate(data, 'expiry_date'),
      createdAt: _requiredDate(data, 'created_at'),
      updatedAt: _requiredDate(data, 'updated_at'),
    );
  }

  static String _requiredString(
    Map<String, dynamic> data,
    String key, {
    String? fallback,
  }) {
    final value = data[key] ?? fallback;
    if (value is! String || value.isEmpty) {
      throw FormatException('Customer field "$key" is missing or invalid.');
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    throw FormatException('Customer field "$key" is missing or invalid.');
  }
}
