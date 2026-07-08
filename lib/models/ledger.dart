class Ledger {
  final String? id;
  final String name;
  final String? categoryName;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? country;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? gstNumber;
  final String? panNumber;
  final String? mailingName;
  final String? alias;
  final String? creditPeriod;
  final double? creditLimit;
  final double openingBalance;
  final double discountPercentage;
  final String? companyName;
  final bool isActive;
  final String? ledgerType;
  final DateTime? updatedAt;

  Ledger({
    this.id,
    required this.name,
    this.categoryName,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.country,
    this.contactPerson,
    this.phone,
    this.email,
    this.gstNumber,
    this.panNumber,
    this.mailingName,
    this.alias,
    this.creditPeriod,
    this.creditLimit,
    this.openingBalance = 0,
    this.discountPercentage = 0,
    this.companyName,
    this.isActive = true,
    this.ledgerType,
    this.updatedAt,
  });

  factory Ledger.fromJson(Map<String, dynamic> json) {
    return Ledger(
      id: json['id']?.toString(),
      name: json['customer_name'] ?? '',
      categoryName: json['customer_category_name'],
      address: json['address'],
      city: json['city'],
      state: json['state'],
      pincode: json['pincode'],
      country: json['country'],
      contactPerson: json['contact_person'],
      phone: json['mobile_number'],
      email: json['email'],
      gstNumber: json['gst_number'],
      panNumber: json['pan_number'],
      mailingName: json['mailing_name'],
      alias: json['alias'],
      creditPeriod: json['credit_period'],
      creditLimit: _toDoubleNullable(json['credit_limit']),
      openingBalance: _toDouble(json['opening_balance']),
      discountPercentage: _toDouble(json['customer_discount_percentage']),
      companyName: json['company_name'],
      isActive: json['is_active'] ?? true,
      ledgerType: json['ledger_type'],
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }

  String get fullAddress {
    final parts = [address, city, state, pincode].where((p) => p != null && p.isNotEmpty);
    return parts.join(', ');
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }

  static double? _toDoubleNullable(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString());
  }
}
