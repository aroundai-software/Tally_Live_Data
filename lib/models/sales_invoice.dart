class SalesInvoice {
  final String? id;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final String customerName;
  final String? customerId;
  final double totalAmount;
  final double gstAmount;
  final double netAmount;
  final double discountAmount;
  final double discountPercentage;
  final double subtotalBeforeDiscount;
  final String? status;
  final String? type;
  final String? notes;
  final String? remarks;
  final String? shippingAddress;
  final String? companyName;
  final String? customerCategoryName;
  final double? roundOff;
  final bool syncedToTally;
  final DateTime? updatedAt;

  SalesInvoice({
    this.id,
    required this.invoiceNumber,
    this.invoiceDate,
    required this.customerName,
    this.customerId,
    this.totalAmount = 0,
    this.gstAmount = 0,
    this.netAmount = 0,
    this.discountAmount = 0,
    this.discountPercentage = 0,
    this.subtotalBeforeDiscount = 0,
    this.status,
    this.type,
    this.notes,
    this.remarks,
    this.shippingAddress,
    this.companyName,
    this.customerCategoryName,
    this.roundOff,
    this.syncedToTally = false,
    this.updatedAt,
  });

  factory SalesInvoice.fromJson(Map<String, dynamic> json) {
    return SalesInvoice(
      id: json['id']?.toString(),
      invoiceNumber: json['invoice_number'] ?? '',
      invoiceDate: json['invoice_date'] != null ? DateTime.tryParse(json['invoice_date']) : null,
      customerName: json['customer_name'] ?? 'Walk-in Customer',
      customerId: json['customer_id']?.toString(),
      totalAmount: _toDouble(json['total_amount']),
      gstAmount: _toDouble(json['gst_amount']),
      netAmount: _toDouble(json['net_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      discountPercentage: _toDouble(json['discount_percentage']),
      subtotalBeforeDiscount: _toDouble(json['subtotal_before_discount']),
      status: json['status'],
      type: json['Type'],
      notes: json['notes'],
      remarks: json['remarks'],
      shippingAddress: json['shipping_address'],
      companyName: json['company_name'],
      customerCategoryName: json['customer_category_name'],
      roundOff: _toDoubleNullable(json['round_off']),
      syncedToTally: json['synced_to_tally'] ?? false,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
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

class InvoiceItem {
  final String? id;
  final String? invoiceId;
  final String productName;
  final String? productCode;
  final int quantity;
  final int freeQuantity;
  final double unitPrice;
  final double gstRate;
  final double gstAmount;
  final double totalAmount;
  final double discountPercentage;
  final double discountAmount;
  final double categoryDiscountPercentage;
  final String? companyName;

  InvoiceItem({
    this.id,
    this.invoiceId,
    required this.productName,
    this.productCode,
    this.quantity = 0,
    this.freeQuantity = 0,
    this.unitPrice = 0,
    this.gstRate = 0,
    this.gstAmount = 0,
    this.totalAmount = 0,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    this.categoryDiscountPercentage = 0,
    this.companyName,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id']?.toString(),
      invoiceId: json['invoice_id']?.toString(),
      productName: json['product_name'] ?? '',
      productCode: json['product_code'],
      quantity: _toInt(json['quantity']),
      freeQuantity: _toInt(json['free_quantity']),
      unitPrice: _toDouble(json['unit_price']),
      gstRate: _toDouble(json['gst_rate']),
      gstAmount: _toDouble(json['gst_amount']),
      totalAmount: _toDouble(json['total_amount']),
      discountPercentage: _toDouble(json['discount_percentage']),
      discountAmount: _toDouble(json['discount_amount']),
      categoryDiscountPercentage: _toDouble(json['category_discount_percentage']),
      companyName: json['company_name'],
    );
  }

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
}
