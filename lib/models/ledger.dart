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
  final double closingBalance;
  final double discountPercentage;
  final String? companyName;
  final bool isActive;
  final String? ledgerType;
  final String? guid;
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
    this.closingBalance = 0,
    this.discountPercentage = 0,
    this.companyName,
    this.isActive = true,
    this.ledgerType,
    this.guid,
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
      closingBalance: _toDouble(json['closing_balance']),
      discountPercentage: _toDouble(json['customer_discount_percentage']),
      companyName: json['company_name'],
      isActive: json['is_active'] ?? true,
      ledgerType: json['ledger_type'],
      guid: json['guid']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }

  /// Placeholder company guid from older sync rows (`00000000-…`).
  bool get hasCompanyGuid {
    final g = guid?.trim() ?? '';
    if (g.isEmpty) return false;
    return !g.startsWith('00000000-0000-0000-0000-000000000000');
  }

  static final RegExp _contactLinePrefix = RegExp(
    r'^\s*(ph|phone|mob|mobile|tel|telephone|email|e-mail)\s*[:.\-]?\s*',
    caseSensitive: false,
  );

  /// Street / mailing lines only — strips embedded phone/email rows that Tally
  /// often stores inside the address field, and avoids re-appending city/state/
  /// pincode when they are already present in the address text.
  String get fullAddress {
    final streetLines = (address ?? '')
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => !_contactLinePrefix.hasMatch(l))
        .toList();
    final base = streetLines.join('\n');
    final extras = <String>[];
    for (final part in [city, state, pincode]) {
      final t = part?.trim() ?? '';
      if (t.isEmpty) continue;
      final haystack = ('$base ${extras.join(' ')}').toLowerCase();
      if (haystack.contains(t.toLowerCase())) continue;
      extras.add(t);
    }
    if (base.isEmpty) return extras.join(', ');
    if (extras.isEmpty) return base;
    return '$base\n${extras.join(', ')}';
  }

  /// Combined ledger group text from type and category (Tally may populate either).
  String get _groupText {
    final parts = <String>[];
    for (final value in [ledgerType, categoryName]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        parts.add(trimmed.toLowerCase());
      }
    }
    return parts.join(' ');
  }

  bool get _isCashOrBank {
    final type = ledgerType?.toLowerCase().trim() ?? '';
    final ledgerName = name.toLowerCase().trim();
    return type.contains('bank') ||
        type.contains('cash') ||
        ledgerName.startsWith('cash') ||
        ledgerName.startsWith('petty cash');
  }

  bool get _isSystemLedger {
    final type = ledgerType?.toLowerCase().trim() ?? '';
    final ledgerName = name.toLowerCase().trim();
    return type.contains('charge') ||
        type.contains('expense') ||
        ledgerName.contains('charges') ||
        ledgerName == 'opening balance' ||
        ledgerName == 'closing balance';
  }

  /// True only when the ledger group is a debtor group.
  bool get isDebtor {
    final group = _groupText;
    if (group.contains('creditor')) return false;
    if (group.contains('debtor')) return true;
    return false;
  }

  /// True only for ledgers explicitly tagged as creditors.
  bool get isCreditor {
    final group = _groupText;
    if (group.contains('debtor')) return false;
    if (group.contains('creditor')) return true;
    if (_isCashOrBank || _isSystemLedger) return false;
    return false;
  }

  bool matchesSearchQuery(String query) {
    if (query.isEmpty) return true;
    bool contains(String? value) =>
        value != null && value.toLowerCase().contains(query);

    return contains(name) || contains(alias) || contains(mailingName);
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
