class PurchaseInvoice {
  final String? id;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final String supplierName;
  final String? supplierId;
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
  final String? supplierCategoryName;
  final double? roundOff;
  final bool syncedToTally;
  final DateTime? updatedAt;

  PurchaseInvoice({
    this.id,
    required this.invoiceNumber,
    this.invoiceDate,
    required this.supplierName,
    this.supplierId,
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
    this.supplierCategoryName,
    this.roundOff,
    this.syncedToTally = false,
    this.updatedAt,
  });

  factory PurchaseInvoice.fromJson(Map<String, dynamic> json) {
    return PurchaseInvoice(
      id: json['id']?.toString(),
      invoiceNumber: json['invoice_number'] ?? '',
      invoiceDate: json['invoice_date'] != null ? DateTime.tryParse(json['invoice_date'])?.toLocal() : null,
      supplierName: json['supplier_name'] ?? 'Walk-in Vendor',
      supplierId: json['supplier_id']?.toString(),
      totalAmount: _toDouble(json['total_amount']),
      gstAmount: _toDouble(json['gst_amount']),
      netAmount: _toDouble(json['net_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      discountPercentage: _toDouble(json['discount_percentage']),
      subtotalBeforeDiscount: _toDouble(json['subtotal_before_discount']),
      status: json['status'],
      type: json['type'],
      notes: json['notes'],
      remarks: json['remarks'],
      shippingAddress: json['shipping_address'],
      companyName: json['company_name'],
      supplierCategoryName: json['supplier_category_name'],
      roundOff: _toDoubleNullable(json['round_off']),
      syncedToTally: json['synced_to_tally'] ?? false,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'])?.toLocal() : null,
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

class PurchaseInvoiceItem {
  final String? id;
  final String? purchaseInvoiceId;
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
  final String? companyName;

  PurchaseInvoiceItem({
    this.id,
    this.purchaseInvoiceId,
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
    this.companyName,
  });

  factory PurchaseInvoiceItem.fromJson(Map<String, dynamic> json) {
    return PurchaseInvoiceItem(
      id: json['id']?.toString(),
      purchaseInvoiceId: json['purchase_invoice_id']?.toString(),
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
