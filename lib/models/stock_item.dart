class StockItem {
  final String? id;
  final String name;
  final String? partNumber;
  final String? unit;
  final String? altUnit;
  final String? parent;
  final String? category;
  final String? alias;
  final String? hsn;
  final String? description;
  final int quantity;
  final double rate;
  final double gstRate;
  final double mrp;
  final double? standardCost;
  final double? standardPrice;
  final double? openingValue;
  final double? floorRate;
  final double offerDiscount;
  final bool isActive;
  final String? imageUrl;
  final String? companyName;
  final DateTime? updatedAt;

  StockItem({
    this.id,
    required this.name,
    this.partNumber,
    this.unit,
    this.altUnit,
    this.parent,
    this.category,
    this.alias,
    this.hsn,
    this.description,
    this.quantity = 0,
    this.rate = 0,
    this.gstRate = 0,
    this.mrp = 0,
    this.standardCost,
    this.standardPrice,
    this.openingValue,
    this.floorRate,
    this.offerDiscount = 0,
    this.isActive = true,
    this.imageUrl,
    this.companyName,
    this.updatedAt,
  });

  factory StockItem.fromJson(Map<String, dynamic> json) {
    return StockItem(
      id: json['id']?.toString(),
      name: json['ItemName'] ?? '',
      partNumber: json['PartNumber'],
      unit: json['ItemUnit'],
      altUnit: json['ItemAltUnit'],
      parent: json['ItemParent'],
      category: json['Category'],
      alias: json['Alias'] ?? json['ItemAlias'],
      hsn: json['hsn'],
      description: json['Description'] ?? json['description'],
      quantity: _toInt(json['ItemQuantity']),
      rate: _toDouble(json['ItemRate']),
      gstRate: _toDouble(json['GstRate']),
      mrp: _toDouble(json['MRP']),
      standardCost: _toDoubleNullable(json['StandardCost']),
      standardPrice: _toDoubleNullable(json['StandardPrice']),
      openingValue: _toDoubleNullable(json['OpeningValue']),
      floorRate: _toDoubleNullable(json['floor_rate']),
      offerDiscount: _toDouble(json['offer_discount_percentage']),
      isActive: json['is_active'] ?? true,
      imageUrl: json['image_url'],
      companyName: json['company_name'],
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }

  double get stockValue => quantity * rate;

  static double _toDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }

  static int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  static double? _toDoubleNullable(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString());
  }
}
