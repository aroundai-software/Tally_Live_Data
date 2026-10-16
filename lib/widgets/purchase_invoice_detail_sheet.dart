import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/purchase_invoice.dart';
import '../services/pdf_service.dart';
import '../services/supabase_service.dart';
import 'summary_card.dart';

Future<void> showPurchaseInvoiceDetailSheet({
  required BuildContext context,
  required PurchaseInvoice invoice,
  SupabaseService? service,
}) {
  final svc = service ?? SupabaseService();
  final dateFormat = DateFormat('dd MMM yyyy');

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.90,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) {
          return Container(
            margin: EdgeInsets.only(bottom: 24, left: 16, right: 16),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.purchaseColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: AppTheme.purchaseColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Invoice #${invoice.invoiceNumber}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                if (invoice.invoiceDate != null)
                                  Text(
                                    dateFormat.format(invoice.invoiceDate!),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_rounded),
                            color: AppTheme.purchaseColor,
                            tooltip: 'Share',
                            onPressed: () async {
                              try {
                                final items = invoice.id != null
                                    ? await svc
                                        .getPurchaseInvoiceItems(invoice.id!)
                                    : <PurchaseInvoiceItem>[];
                                await PdfService.sharePurchaseInvoice(
                                    invoice, items);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: AppTheme.textSecondary,
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _detailSection('Supplier Details', [
                        _detailItem('Supplier', invoice.supplierName),
                        if (invoice.shippingAddress != null &&
                            invoice.shippingAddress!.isNotEmpty)
                          _detailItem('Ship To', invoice.shippingAddress!),
                        if (invoice.supplierCategoryName != null &&
                            invoice.supplierCategoryName!.isNotEmpty)
                          _detailItem(
                              'Category', invoice.supplierCategoryName!),
                        if (invoice.type != null && invoice.type!.isNotEmpty)
                          _detailItem('Type', invoice.type!),
                      ]),
                      if (invoice.id != null) ...[
                        const SizedBox(height: 16),
                        FutureBuilder<List<PurchaseInvoiceItem>>(
                          future: svc.getPurchaseInvoiceItems(invoice.id!),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              );
                            }
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _buildItemsTable(snapshot.data!);
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      _detailSection('Amount Details', [
                        if (invoice.subtotalBeforeDiscount > 0)
                          _detailItem(
                            'Subtotal',
                            formatCurrency(invoice.subtotalBeforeDiscount),
                          ),
                        if (invoice.discountAmount > 0)
                          _detailItem(
                            'Discount (${invoice.discountPercentage.toStringAsFixed(1)}%)',
                            formatCurrency(invoice.discountAmount),
                          ),
                        _detailItem(
                            'Net Amount', formatCurrency(invoice.netAmount)),
                        _detailItem(
                            'GST Amount', formatCurrency(invoice.gstAmount)),
                        if (invoice.roundOff != null && invoice.roundOff! != 0)
                          _detailItem(
                              'Round Off', formatCurrency(invoice.roundOff!)),
                        _detailItem(
                          'Total Amount',
                          formatCurrency(invoice.totalAmount),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Status', [
                        if (invoice.status != null)
                          _detailItem('Status', invoice.status!),
                        _detailItem(
                          'Tally Synced',
                          invoice.syncedToTally ? 'Yes' : 'No',
                        ),
                        if (invoice.remarks != null &&
                            invoice.remarks!.isNotEmpty)
                          _detailItem('Remarks', invoice.remarks!),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _detailSection(String title, List<Widget> children) {
  return Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

Widget _detailItem(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildItemsTable(List<PurchaseInvoiceItem> items) {
  return Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 10),
        ...items.map(
          (item) => Container(
            margin: EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.productName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      formatCurrency(item.totalAmount),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.purchaseColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _miniChip('Qty: ${item.quantity}'),
                    _miniChip(
                        'Rate: \u20B9${item.unitPrice.toStringAsFixed(2)}'),
                    _miniChip('GST: ${item.gstRate.toStringAsFixed(0)}%'),
                    if (item.freeQuantity > 0)
                      _miniChip('Free: ${item.freeQuantity}'),
                    if (item.discountAmount > 0)
                      _miniChip(
                          'Disc: \u20B9${item.discountAmount.toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _miniChip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
