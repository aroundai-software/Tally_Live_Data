import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/daybook_entry.dart';
import '../models/ledger.dart';
import '../models/purchase_invoice.dart';
import '../models/sales_invoice.dart';
import '../services/pdf_service.dart';
import '../services/supabase_service.dart';

/// Opens a centered popup with one voucher's details + Share / Download.
Future<void> showLedgerVoucherDetailSheet({
  required BuildContext context,
  required DaybookEntry entry,
  required Ledger ledger,
  String? companyName,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => LedgerVoucherDetailSheet(
      entry: entry,
      ledger: ledger,
      companyName: companyName,
    ),
  );
}

class LedgerVoucherDetailSheet extends StatefulWidget {
  final DaybookEntry entry;
  final Ledger ledger;
  final String? companyName;

  const LedgerVoucherDetailSheet({
    super.key,
    required this.entry,
    required this.ledger,
    this.companyName,
  });

  @override
  State<LedgerVoucherDetailSheet> createState() => _LedgerVoucherDetailSheetState();
}

class _LedgerVoucherDetailSheetState extends State<LedgerVoucherDetailSheet> {
  final _service = SupabaseService();
  final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9');

  bool _loadingLinked = true;
  bool _busyExport = false;
  SalesInvoice? _salesInvoice;
  PurchaseInvoice? _purchaseInvoice;
  List<InvoiceItem> _salesItems = const [];
  List<PurchaseInvoiceItem> _purchaseItems = const [];

  DaybookEntry get entry => widget.entry;

  @override
  void initState() {
    super.initState();
    _loadLinkedInvoice();
  }

  bool get _looksLikeSales {
    final vt = entry.voucherType.toLowerCase();
    return vt.contains('sales') || vt.contains('sale');
  }

  bool get _looksLikePurchase {
    final vt = entry.voucherType.toLowerCase();
    return vt.contains('purchase');
  }

  Future<void> _loadLinkedInvoice() async {
    final company = widget.companyName?.trim() ?? '';
    final number = entry.voucherNumber?.trim() ?? '';
    if (company.isEmpty || number.isEmpty || (!_looksLikeSales && !_looksLikePurchase)) {
      if (mounted) setState(() => _loadingLinked = false);
      return;
    }

    try {
      if (_looksLikeSales) {
        final invoice = await _service.findSalesInvoiceByNumber(
          companyName: company,
          invoiceNumber: number,
          partyName: widget.ledger.name,
        );
        List<InvoiceItem> items = const [];
        if (invoice?.id != null) {
          items = await _service.getInvoiceItems(invoice!.id!);
        }
        if (!mounted) return;
        setState(() {
          _salesInvoice = invoice;
          _salesItems = items;
          _loadingLinked = false;
        });
        return;
      }

      if (_looksLikePurchase) {
        final invoice = await _service.findPurchaseInvoiceByNumber(
          companyName: company,
          invoiceNumber: number,
          partyName: widget.ledger.name,
        );
        List<PurchaseInvoiceItem> items = const [];
        if (invoice?.id != null) {
          items = await _service.getPurchaseInvoiceItems(invoice!.id!);
        }
        if (!mounted) return;
        setState(() {
          _purchaseInvoice = invoice;
          _purchaseItems = items;
          _loadingLinked = false;
        });
        return;
      }
    } catch (_) {
      // Fall back to voucher-only detail.
    }

    if (mounted) setState(() => _loadingLinked = false);
  }

  Future<void> _share() async {
    if (_busyExport) return;
    setState(() => _busyExport = true);
    try {
      if (_salesInvoice != null) {
        await PdfService.shareSalesInvoice(
          _salesInvoice!,
          _salesItems,
          ledger: widget.ledger,
        );
      } else if (_purchaseInvoice != null) {
        await PdfService.sharePurchaseInvoice(
          _purchaseInvoice!,
          _purchaseItems,
          ledger: widget.ledger,
        );
      } else {
        await PdfService.shareDaybookVoucher(
          entry: entry,
          partyName: widget.ledger.name,
          companyName: widget.companyName,
          ledger: widget.ledger,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  Future<void> _download() async {
    if (_busyExport) return;
    setState(() => _busyExport = true);
    try {
      if (_salesInvoice != null) {
        await PdfService.downloadSalesInvoice(
          _salesInvoice!,
          _salesItems,
          ledger: widget.ledger,
        );
      } else if (_purchaseInvoice != null) {
        await PdfService.downloadPurchaseInvoice(
          _purchaseInvoice!,
          _purchaseItems,
          ledger: widget.ledger,
        );
      } else {
        await PdfService.downloadDaybookVoucher(
          entry: entry,
          partyName: widget.ledger.name,
          companyName: widget.companyName,
          ledger: widget.ledger,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebit = entry.isDebit;
    final amountColor = isDebit ? Colors.red.shade700 : Colors.green.shade700;
    final screen = MediaQuery.sizeOf(context);
    final maxHeight = screen.height * 0.85;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Share',
                    onPressed: _busyExport ? null : _share,
                    icon: _busyExport
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_rounded),
                    color: AppTheme.primaryColor,
                  ),
                  IconButton(
                    tooltip: 'Download',
                    onPressed: _busyExport ? null : _download,
                    icon: const Icon(Icons.download_rounded),
                    color: AppTheme.primaryColor,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: amountColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isDebit ? Icons.south_west_rounded : Icons.north_east_rounded,
                            color: amountColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.particulars ?? entry.ledgerName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.date != null
                                    ? DateFormat('EEEE, d MMM yyyy').format(entry.date!)
                                    : 'Date unavailable',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildLedgerDetails(),
                    const SizedBox(height: 14),
                    _section('Voucher', [
                      _row('Party', widget.ledger.name),
                      _row('Type', entry.voucherType),
                      if (entry.voucherNumber != null && entry.voucherNumber!.isNotEmpty)
                        _row('Voucher No.', entry.voucherNumber!),
                      _row(
                        isDebit ? 'Debit' : 'Credit',
                        _currency.format(entry.amount.abs()),
                        valueColor: amountColor,
                      ),
                    ]),
                    if (entry.narration != null && entry.narration!.trim().isNotEmpty) ...[
                      SizedBox(height: 14),
                      _section('Narration', [
                        Text(
                          entry.narration!.trim(),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ]),
                    ],
                    if (_loadingLinked) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ] else if (_salesInvoice != null) ...[
                      const SizedBox(height: 14),
                      _buildSalesExtras(_salesInvoice!),
                    ] else if (_purchaseInvoice != null) ...[
                      const SizedBox(height: 14),
                      _buildPurchaseExtras(_purchaseInvoice!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerDetails() {
    final ledger = widget.ledger;
    final rows = <Widget>[
      _row('Name', ledger.name),
      if (ledger.ledgerType != null && ledger.ledgerType!.trim().isNotEmpty)
        _row('Group', ledger.ledgerType!.trim()),
      if (ledger.categoryName != null && ledger.categoryName!.trim().isNotEmpty)
        _row('Category', ledger.categoryName!.trim()),
      if (ledger.gstNumber != null && ledger.gstNumber!.trim().isNotEmpty)
        _row('GSTIN', ledger.gstNumber!.trim()),
      if (ledger.panNumber != null && ledger.panNumber!.trim().isNotEmpty)
        _row('PAN', ledger.panNumber!.trim()),
      if (ledger.phone != null && ledger.phone!.trim().isNotEmpty)
        _row('Mobile', ledger.phone!.trim()),
      if (ledger.email != null && ledger.email!.trim().isNotEmpty)
        _row('Email', ledger.email!.trim()),
      if (ledger.contactPerson != null && ledger.contactPerson!.trim().isNotEmpty)
        _row('Contact', ledger.contactPerson!.trim()),
      if (ledger.fullAddress.isNotEmpty) _row('Address', ledger.fullAddress),
      if (ledger.creditPeriod != null && ledger.creditPeriod!.trim().isNotEmpty)
        _row('Credit Period', ledger.creditPeriod!.trim()),
      if (ledger.creditLimit != null && ledger.creditLimit! > 0)
        _row('Credit Limit', _currency.format(ledger.creditLimit!)),
      _row('Opening Balance', _currency.format(ledger.openingBalance.abs())),
      _row('Closing Balance', _currency.format(ledger.closingBalance.abs())),
    ];
    return _section('Ledger Details', rows);
  }

  Widget _buildSalesExtras(SalesInvoice invoice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Invoice', [
          _row('Invoice No.', invoice.invoiceNumber),
          _row('Customer', invoice.customerName),
          if (invoice.status != null && invoice.status!.isNotEmpty) _row('Status', invoice.status!),
          if (invoice.gstAmount > 0) _row('GST', _currency.format(invoice.gstAmount)),
          _row('Total', _currency.format(invoice.totalAmount)),
        ]),
        if (_salesItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          _itemsSection(
            _salesItems
                .map(
                  (e) => _ItemLine(
                    name: e.productName,
                    qty: e.quantity,
                    rate: e.unitPrice,
                    gst: e.gstRate,
                    amount: e.totalAmount,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildPurchaseExtras(PurchaseInvoice invoice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Invoice', [
          _row('Invoice No.', invoice.invoiceNumber),
          _row('Supplier', invoice.supplierName),
          if (invoice.status != null && invoice.status!.isNotEmpty) _row('Status', invoice.status!),
          if (invoice.gstAmount > 0) _row('GST', _currency.format(invoice.gstAmount)),
          _row('Total', _currency.format(invoice.totalAmount)),
        ]),
        if (_purchaseItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          _itemsSection(
            _purchaseItems
                .map(
                  (e) => _ItemLine(
                    name: e.productName,
                    qty: e.quantity,
                    rate: e.unitPrice,
                    gst: e.gstRate,
                    amount: e.totalAmount,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
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

  Widget _row(String label, String value, {Color? valueColor}) {
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
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsSection(List<_ItemLine> items) {
    return _section(
      'Items',
      items
          .map(
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
                          item.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        _currency.format(item.amount),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Qty ${item.qty} · Rate ${_currency.format(item.rate)} · GST ${item.gst.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ItemLine {
  final String name;
  final double qty;
  final double rate;
  final double gst;
  final double amount;

  const _ItemLine({
    required this.name,
    required this.qty,
    required this.rate,
    required this.gst,
    required this.amount,
  });
}
