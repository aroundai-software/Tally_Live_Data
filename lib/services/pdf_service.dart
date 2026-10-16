import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/daybook_entry.dart';
import '../models/ledger.dart';
import '../models/receivable_payable.dart';
import '../models/sales_invoice.dart';
import '../models/purchase_invoice.dart';
import 'supabase_service.dart';

/// Shared professional PDF templates for invoices, vouchers, outstanding bills,
/// and ledger statements across the app.
class PdfService {
  // Palette — restrained navy letterhead (business document, not marketing).
  static const _ink = PdfColor.fromInt(0xFF152033);
  static const _muted = PdfColor.fromInt(0xFF5C6B80);
  static const _line = PdfColor.fromInt(0xFFD5DCE6);
  static const _soft = PdfColor.fromInt(0xFFF4F6F9);
  static const _accent = PdfColor.fromInt(0xFF0B3D91);
  static const _accentSoft = PdfColor.fromInt(0xFFE8EEF8);

  static final _dateFmt = DateFormat('dd MMM yyyy');
  static final _dateShortFmt = DateFormat('dd-MMM-yy');
  static final _currFmt =
      NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);
  static final _plainAmtFmt = NumberFormat('#,##,##0.00', 'en_IN');

  // ── Public entry points ──────────────────────────────────────────────────

  static Future<void> shareSalesInvoice(
    SalesInvoice invoice,
    List<InvoiceItem> items, {
    Ledger? ledger,
  }) async {
    final party = ledger ??
        await _resolvePartyLedger(
          companyName: invoice.companyName,
          partyName: invoice.customerName,
        );
    final pdf = await _generateSalesPdf(invoice, items, ledger: party);
    final safeName = invoice.invoiceNumber.replaceAll(RegExp(r'[/\\]'), '_');
    await _sharePdf(pdf, 'Invoice_$safeName.pdf');
  }

  static Future<void> downloadSalesInvoice(
    SalesInvoice invoice,
    List<InvoiceItem> items, {
    Ledger? ledger,
  }) async {
    final party = ledger ??
        await _resolvePartyLedger(
          companyName: invoice.companyName,
          partyName: invoice.customerName,
        );
    final pdf = await _generateSalesPdf(invoice, items, ledger: party);
    final safeName = invoice.invoiceNumber.replaceAll(RegExp(r'[/\\]'), '_');
    await _downloadPdf(pdf, 'Invoice_$safeName.pdf');
  }

  static Future<void> sharePurchaseInvoice(
    PurchaseInvoice invoice,
    List<PurchaseInvoiceItem> items, {
    Ledger? ledger,
  }) async {
    final party = ledger ??
        await _resolvePartyLedger(
          companyName: invoice.companyName,
          partyName: invoice.supplierName,
        );
    final pdf = await _generatePurchasePdf(invoice, items, ledger: party);
    final safeName = invoice.invoiceNumber.replaceAll(RegExp(r'[/\\]'), '_');
    await _sharePdf(pdf, 'Purchase_$safeName.pdf');
  }

  static Future<void> downloadPurchaseInvoice(
    PurchaseInvoice invoice,
    List<PurchaseInvoiceItem> items, {
    Ledger? ledger,
  }) async {
    final party = ledger ??
        await _resolvePartyLedger(
          companyName: invoice.companyName,
          partyName: invoice.supplierName,
        );
    final pdf = await _generatePurchasePdf(invoice, items, ledger: party);
    final safeName = invoice.invoiceNumber.replaceAll(RegExp(r'[/\\]'), '_');
    await _downloadPdf(pdf, 'Purchase_$safeName.pdf');
  }

  /// Look up ledger master for Bill To / Vendor contact details on PDFs.
  static Future<Ledger?> _resolvePartyLedger({
    required String? companyName,
    required String partyName,
  }) async {
    final company = companyName?.trim() ?? '';
    final name = partyName.trim();
    if (company.isEmpty || name.isEmpty) return null;
    try {
      final matches = await SupabaseService().getLedgersByName(
        companyName: company,
        ledgerName: name,
      );
      if (matches.isEmpty) return null;
      // Prefer the row that has the richest contact/address data.
      matches.sort((a, b) {
        int score(Ledger l) {
          var s = 0;
          if (l.fullAddress.trim().isNotEmpty) s += 4;
          if ((l.phone ?? '').trim().isNotEmpty) s += 2;
          if ((l.email ?? '').trim().isNotEmpty) s += 2;
          if ((l.gstNumber ?? '').trim().isNotEmpty) s += 1;
          return s;
        }

        return score(b).compareTo(score(a));
      });
      return matches.first;
    } catch (_) {
      return null;
    }
  }

  static Future<void> shareDaybookVoucher({
    required DaybookEntry entry,
    required String partyName,
    String? companyName,
    Ledger? ledger,
  }) async {
    final pdf = await _generateVoucherPdf(
      entry: entry,
      partyName: partyName,
      companyName: companyName,
      ledger: ledger,
    );
    await _sharePdf(pdf, _voucherFilename(entry));
  }

  static Future<void> downloadDaybookVoucher({
    required DaybookEntry entry,
    required String partyName,
    String? companyName,
    Ledger? ledger,
  }) async {
    final pdf = await _generateVoucherPdf(
      entry: entry,
      partyName: partyName,
      companyName: companyName,
      ledger: ledger,
    );
    await _downloadPdf(pdf, _voucherFilename(entry));
  }

  static Future<void> shareOutstandingBill({
    required OutstandingRecord record,
    required bool isReceivable,
  }) async {
    final pdf = await _generateOutstandingPdf(
      record: record,
      isReceivable: isReceivable,
    );
    final bill = record.invoiceNumber.trim().isNotEmpty
        ? record.invoiceNumber.replaceAll(RegExp(r'[/\\]'), '_')
        : 'bill';
    final prefix = isReceivable ? 'Receivable' : 'Payable';
    await _sharePdf(pdf, '${prefix}_$bill.pdf');
  }

  /// Build a ledger account statement PDF (used by share + download).
  static Future<pw.Document> generateLedgerStatementPdf({
    required String companyName,
    required Ledger ledger,
    required List<DaybookEntry> transactions,
    required String dateRangeText,
    required double openingBalance,
    required double totalDebits,
    required double totalCredits,
    required double closingBalance,
  }) async {
    final fonts = await _loadFonts();
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    final pdf = pw.Document(theme: theme);

    final sorted = List<DaybookEntry>.from(transactions)
      ..sort((a, b) {
        if (a.date == null || b.date == null) return 0;
        return a.date!.compareTo(b.date!);
      });

    final tableData = <List<String>>[];
    for (final entry in sorted) {
      final dateStr =
          entry.date != null ? _dateShortFmt.format(entry.date!) : '';
      final prefix = entry.isDebit ? 'To ' : 'By ';
      final particulars = prefix + (entry.particulars ?? entry.ledgerName);
      tableData.add([
        dateStr,
        particulars,
        entry.voucherType,
        entry.voucherNumber ?? '',
        entry.isDebit ? _plainAmt(entry.amount) : '',
        !entry.isDebit ? _plainAmt(entry.amount) : '',
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        header: (ctx) => _docLetterhead(
          companyName: companyName,
          docTitle: 'LEDGER ACCOUNT',
          regular: fonts.regular,
          bold: fonts.bold,
          pageNumber: ctx.pageNumber,
          pageCount: ctx.pagesCount,
        ),
        footer: (ctx) => _pageFooter(fonts.regular, ctx.pageNumber, ctx.pagesCount),
        build: (_) => [
          pw.SizedBox(height: 12),
          _sectionCard(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  ledger.name,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 13,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Statement of Account',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: _muted,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _metaLine(
                        'Period',
                        dateRangeText,
                        fonts.regular,
                        fonts.bold,
                      ),
                    ),
                    if (ledger.gstNumber != null &&
                        ledger.gstNumber!.trim().isNotEmpty)
                      pw.Expanded(
                        child: _metaLine(
                          'GSTIN',
                          ledger.gstNumber!.trim(),
                          fonts.regular,
                          fonts.bold,
                        ),
                      ),
                  ],
                ),
                if (ledger.fullAddress.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    ledger.fullAddress.trim(),
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 9,
                      color: _muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          _dataTable(
            headers: const [
              'Date',
              'Particulars',
              'Vch Type',
              'Vch No.',
              'Debit',
              'Credit',
            ],
            data: tableData.isEmpty
                ? [
                    ['', 'No transactions in this period', '', '', '', '']
                  ]
                : tableData,
            regular: fonts.regular,
            bold: fonts.bold,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.6),
              1: const pw.FlexColumnWidth(4.2),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.7),
              5: const pw.FlexColumnWidth(1.7),
            },
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 12),
          _statementTotals(
            openingBalance: openingBalance,
            totalDebits: totalDebits,
            totalCredits: totalCredits,
            closingBalance: closingBalance,
            regular: fonts.regular,
            bold: fonts.bold,
          ),
          pw.SizedBox(height: 22),
          _signatureBlock(fonts.regular, fonts.bold, companyName: companyName),
        ],
      ),
    );
    return pdf;
  }

  // ── Generators ────────────────────────────────────────────────────────────

  static String _voucherFilename(DaybookEntry entry) {
    final ref = (entry.voucherNumber ?? entry.voucherType)
        .replaceAll(RegExp(r'[/\\]'), '_');
    return 'Voucher_$ref.pdf';
  }

  static Future<pw.Document> _generateOutstandingPdf({
    required OutstandingRecord record,
    required bool isReceivable,
  }) async {
    final fonts = await _loadFonts();
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    final displayAmount = record.closingBalance != 0
        ? record.closingBalance.abs()
        : record.amount.abs();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOverdue = record.isOverdue ||
        (record.dueDate != null && record.dueDate!.isBefore(today));
    var overdueDays = record.overdueDays ?? 0;
    if (overdueDays <= 0 &&
        record.dueDate != null &&
        record.dueDate!.isBefore(today)) {
      overdueDays = today
          .difference(DateTime(record.dueDate!.year, record.dueDate!.month,
              record.dueDate!.day))
          .inDays;
    }

    final company = (record.companyName ?? '').trim().isNotEmpty
        ? record.companyName!.trim()
        : 'TallyLive';
    final title = isReceivable ? 'RECEIVABLE STATEMENT' : 'PAYABLE STATEMENT';
    final partyLabel = isReceivable ? 'Customer' : 'Supplier';

    final ledger = await _resolvePartyLedger(
      companyName: record.companyName,
      partyName: record.customerName,
    );
    final address = (ledger?.fullAddress ?? '').trim();
    final phone = (ledger?.phone ?? '').trim().isNotEmpty
        ? ledger!.phone!.trim()
        : (record.mobile ?? '').trim();
    final email = (ledger?.email ?? '').trim();

    final meta = <MapEntry<String, String>>[
      if (record.invoiceNumber.trim().isNotEmpty)
        MapEntry('Bill No.', record.invoiceNumber.trim()),
      if ((record.billType ?? '').trim().isNotEmpty)
        MapEntry('Type', record.billType!.trim()),
      if (record.date != null)
        MapEntry('Bill Date', _dateFmt.format(record.date!)),
      if (record.dueDate != null)
        MapEntry('Due Date', _dateFmt.format(record.dueDate!)),
      if (record.creditDays != null && record.creditDays! > 0)
        MapEntry('Credit Days', '${record.creditDays}'),
      MapEntry(
        'Status',
        isOverdue
            ? (overdueDays > 0 ? 'Overdue · ${overdueDays}d' : 'Overdue')
            : 'Current',
      ),
    ];

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        header: (ctx) => _docLetterhead(
          companyName: company,
          docTitle: title,
          regular: fonts.regular,
          bold: fonts.bold,
          pageNumber: ctx.pageNumber,
          pageCount: ctx.pagesCount,
        ),
        footer: (ctx) => _pageFooter(fonts.regular, ctx.pageNumber, ctx.pagesCount),
        build: (_) => [
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 6,
                child: _partyCard(
                  label: partyLabel,
                  name: record.customerName,
                  address: address.isNotEmpty ? address : null,
                  regular: fonts.regular,
                  bold: fonts.bold,
                  extraLines: [
                    if (phone.isNotEmpty) 'Phone: $phone',
                    if (email.isNotEmpty) 'Email: $email',
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 5,
                child: _metaCard(meta, fonts.regular, fonts.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          _amountHighlight(
            label: 'Outstanding Amount',
            amount: displayAmount,
            regular: fonts.regular,
            bold: fonts.bold,
          ),
          pw.SizedBox(height: 12),
          _sectionCard(
            child: pw.Column(
              children: [
                if (record.openingBalance != 0)
                  _kvRow(
                    'Opening Balance',
                    _currFmt.format(record.openingBalance.abs()),
                    fonts.regular,
                    fonts.bold,
                  ),
                if (record.closingBalance != 0)
                  _kvRow(
                    'Closing Balance',
                    _currFmt.format(record.closingBalance.abs()),
                    fonts.regular,
                    fonts.bold,
                  ),
                _kvRow(
                  'Amount in Words',
                  _amountInWords(displayAmount),
                  fonts.regular,
                  fonts.bold,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          _signatureBlock(fonts.regular, fonts.bold, companyName: company),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _generateVoucherPdf({
    required DaybookEntry entry,
    required String partyName,
    String? companyName,
    Ledger? ledger,
  }) async {
    final fonts = await _loadFonts();
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    final dateStr =
        entry.date != null ? _dateFmt.format(entry.date!) : '—';
    final side = entry.isDebit ? 'Debit' : 'Credit';
    final amount = entry.amount.abs();
    final company =
        companyName?.trim().isNotEmpty == true ? companyName!.trim() : 'TallyLive';

    final meta = <MapEntry<String, String>>[
      MapEntry('Date', dateStr),
      MapEntry('Voucher Type', entry.voucherType),
      if (entry.voucherNumber != null && entry.voucherNumber!.trim().isNotEmpty)
        MapEntry('Voucher No.', entry.voucherNumber!.trim()),
      MapEntry('Entry', side),
    ];

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        header: (ctx) => _docLetterhead(
          companyName: company,
          docTitle: 'VOUCHER',
          regular: fonts.regular,
          bold: fonts.bold,
          pageNumber: ctx.pageNumber,
          pageCount: ctx.pagesCount,
        ),
        footer: (ctx) => _pageFooter(fonts.regular, ctx.pageNumber, ctx.pagesCount),
        build: (_) => [
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 6,
                child: _partyCard(
                  label: 'Party / Ledger',
                  name: partyName,
                  address: ledger?.fullAddress.trim().isNotEmpty == true
                      ? ledger!.fullAddress.trim()
                      : null,
                  regular: fonts.regular,
                  bold: fonts.bold,
                  ledger: ledger,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 5,
                child: _metaCard(meta, fonts.regular, fonts.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _sectionCard(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _kvRow(
                  'Particulars',
                  (entry.particulars ?? entry.ledgerName).trim(),
                  fonts.regular,
                  fonts.bold,
                ),
                if (entry.narration != null &&
                    entry.narration!.trim().isNotEmpty)
                  _kvRow(
                    'Narration',
                    entry.narration!.trim(),
                    fonts.regular,
                    fonts.bold,
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          _amountHighlight(
            label: '$side Amount',
            amount: amount,
            regular: fonts.regular,
            bold: fonts.bold,
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            _amountInWords(amount),
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9,
              color: _muted,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.SizedBox(height: 28),
          _signatureBlock(fonts.regular, fonts.bold, companyName: company),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _generateSalesPdf(
    SalesInvoice invoice,
    List<InvoiceItem> items, {
    Ledger? ledger,
  }) async {
    final fonts = await _loadFonts();
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    final address = _partyAddress(ledger, invoice.shippingAddress);
    final company = invoice.companyName ?? 'Company';

    final meta = <MapEntry<String, String>>[
      MapEntry('Invoice No.', invoice.invoiceNumber),
      if (invoice.invoiceDate != null)
        MapEntry('Date', _dateFmt.format(invoice.invoiceDate!)),
      if ((invoice.type ?? '').trim().isNotEmpty)
        MapEntry('Type', invoice.type!.trim()),
    ];

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        header: (ctx) => _docLetterhead(
          companyName: company,
          docTitle: 'TAX INVOICE',
          regular: fonts.regular,
          bold: fonts.bold,
          pageNumber: ctx.pageNumber,
          pageCount: ctx.pagesCount,
        ),
        footer: (ctx) => _pageFooter(fonts.regular, ctx.pageNumber, ctx.pagesCount),
        build: (_) => [
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 6,
                child: _partyCard(
                  label: 'Bill To',
                  name: invoice.customerName,
                  address: address,
                  regular: fonts.regular,
                  bold: fonts.bold,
                  ledger: ledger,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 5,
                child: _metaCard(meta, fonts.regular, fonts.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _itemsTable(
            items
                .map((e) => {
              'name': e.productName,
              'qty': e.quantity,
              'rate': e.unitPrice,
              'gst': e.gstRate,
                      'gstAmount': e.gstAmount,
              'amount': e.totalAmount,
                    })
                .toList(),
            fonts.regular,
            fonts.bold,
          ),
          pw.SizedBox(height: 14),
          _invoiceTotalsBlock(
            subtotal: invoice.subtotalBeforeDiscount > 0
                ? invoice.subtotalBeforeDiscount
                : invoice.netAmount,
            discount: invoice.discountAmount,
            netAmount: invoice.netAmount,
            gst: invoice.gstAmount,
            roundOff: invoice.roundOff ?? 0,
            total: invoice.totalAmount,
            regular: fonts.regular,
            bold: fonts.bold,
            notes: invoice.notes ?? invoice.remarks,
            // Breakdown only when multiple lines — single-line Amount already has rate+GST.
            showBreakdown: items.length > 1,
          ),
          pw.SizedBox(height: 24),
          _signatureBlock(fonts.regular, fonts.bold, companyName: company),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _generatePurchasePdf(
    PurchaseInvoice invoice,
    List<PurchaseInvoiceItem> items, {
    Ledger? ledger,
  }) async {
    final fonts = await _loadFonts();
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    final address = _partyAddress(ledger, invoice.shippingAddress);
    final company = invoice.companyName ?? 'Company';

    final meta = <MapEntry<String, String>>[
      MapEntry('Invoice No.', invoice.invoiceNumber),
      if (invoice.invoiceDate != null)
        MapEntry('Date', _dateFmt.format(invoice.invoiceDate!)),
      if ((invoice.type ?? '').trim().isNotEmpty)
        MapEntry('Type', invoice.type!.trim()),
    ];

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 40),
        header: (ctx) => _docLetterhead(
          companyName: company,
          docTitle: 'PURCHASE INVOICE',
          regular: fonts.regular,
          bold: fonts.bold,
          pageNumber: ctx.pageNumber,
          pageCount: ctx.pagesCount,
        ),
        footer: (ctx) => _pageFooter(fonts.regular, ctx.pageNumber, ctx.pagesCount),
        build: (_) => [
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 6,
                child: _partyCard(
                  label: 'Vendor',
                  name: invoice.supplierName,
                  address: address,
                  regular: fonts.regular,
                  bold: fonts.bold,
                  ledger: ledger,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 5,
                child: _metaCard(meta, fonts.regular, fonts.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          _itemsTable(
            items
                .map((e) => {
              'name': e.productName,
              'qty': e.quantity,
              'rate': e.unitPrice,
              'gst': e.gstRate,
                      'gstAmount': e.gstAmount,
              'amount': e.totalAmount,
                    })
                .toList(),
            fonts.regular,
            fonts.bold,
          ),
          pw.SizedBox(height: 14),
          _invoiceTotalsBlock(
            subtotal: invoice.subtotalBeforeDiscount > 0
                ? invoice.subtotalBeforeDiscount
                : invoice.netAmount,
            discount: invoice.discountAmount,
            netAmount: invoice.netAmount,
            gst: invoice.gstAmount,
            roundOff: invoice.roundOff ?? 0,
            total: invoice.totalAmount,
            regular: fonts.regular,
            bold: fonts.bold,
            notes: invoice.notes ?? invoice.remarks,
            showBreakdown: items.length > 1,
          ),
          pw.SizedBox(height: 24),
          _signatureBlock(fonts.regular, fonts.bold, companyName: company),
        ],
      ),
    );
    return pdf;
  }

  // ── Shared layout ─────────────────────────────────────────────────────────

  static Future<({pw.Font regular, pw.Font bold})> _loadFonts() async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return (regular: regular, bold: bold);
  }

  static String? _partyAddress(Ledger? ledger, String? fallback) {
    final fromLedger = ledger?.fullAddress.trim() ?? '';
    if (fromLedger.isNotEmpty) return fromLedger;
    final fromInvoice = fallback?.trim() ?? '';
    return fromInvoice.isNotEmpty ? fromInvoice : null;
  }

  static String _plainAmt(double amount) {
    if (amount.abs() < 0.001) return '';
    return _plainAmtFmt.format(amount.abs());
  }

  static pw.Widget _docLetterhead({
    required String companyName,
    required String docTitle,
    required pw.Font regular,
    required pw.Font bold,
    required int pageNumber,
    required int pageCount,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 3, color: _accent),
        pw.SizedBox(height: 12),
        pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 15,
                      color: _ink,
              ),
                  ),
                  pw.SizedBox(height: 3),
              pw.Text(
                    'Generated by TallyLive',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 8,
                      color: _muted,
                    ),
              ),
            ],
          ),
        ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: _accentSoft,
                border: pw.Border.all(color: _line),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                docTitle,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 10,
                  color: _accent,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 1, color: _line),
      ],
    );
  }

  static pw.Widget _pageFooter(pw.Font regular, int page, int pages) {
    return pw.Column(
      children: [
        pw.Container(height: 1, color: _line),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'This is a computer-generated document.',
              style: pw.TextStyle(font: regular, fontSize: 8, color: _muted),
            ),
            pw.Text(
              'Page $page of $pages',
              style: pw.TextStyle(font: regular, fontSize: 8, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _sectionCard({required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _soft,
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: child,
    );
  }

  static pw.Widget _partyCard({
    required String label,
    required String name,
    required String? address,
    required pw.Font regular,
    required pw.Font bold,
    Ledger? ledger,
    List<String> extraLines = const [],
  }) {
    final resolvedAddress = (address != null && address.trim().isNotEmpty)
        ? address.trim()
        : (ledger?.fullAddress.trim().isNotEmpty == true
            ? ledger!.fullAddress.trim()
            : null);
    final detailLines = <String>[
      ...extraLines,
      if (ledger?.phone != null && ledger!.phone!.trim().isNotEmpty)
        'Phone: ${ledger.phone!.trim()}',
      if (ledger?.email != null && ledger!.email!.trim().isNotEmpty)
        'Email: ${ledger.email!.trim()}',
      if (ledger?.gstNumber != null && ledger!.gstNumber!.trim().isNotEmpty)
        'GSTIN: ${ledger.gstNumber!.trim()}',
      if (ledger?.panNumber != null && ledger!.panNumber!.trim().isNotEmpty)
        'PAN: ${ledger.panNumber!.trim()}',
      if (ledger?.contactPerson != null &&
          ledger!.contactPerson!.trim().isNotEmpty)
        'Contact: ${ledger.contactPerson!.trim()}',
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
          child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
            label.toUpperCase(),
                style: pw.TextStyle(
                  font: bold,
              fontSize: 8,
              color: _accent,
              letterSpacing: 0.7,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
            name,
            style: pw.TextStyle(font: bold, fontSize: 12, color: _ink),
              ),
          if (resolvedAddress != null) ...[
            pw.SizedBox(height: 4),
                pw.Text(
              resolvedAddress,
              style: pw.TextStyle(font: regular, fontSize: 9, color: _ink),
            ),
          ],
          if (detailLines.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Container(height: 1, color: _line),
            pw.SizedBox(height: 6),
            for (final line in detailLines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  line,
                  style:
                      pw.TextStyle(font: regular, fontSize: 9, color: _muted),
          ),
        ),
      ],
        ],
      ),
    );
  }

  static pw.Widget _metaCard(
    List<MapEntry<String, String>> rows,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _soft,
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) pw.SizedBox(height: 6),
            pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
                pw.SizedBox(
                  width: 78,
                  child: pw.Text(
                    rows[i].key,
              style: pw.TextStyle(
                      font: regular,
                      fontSize: 9,
                      color: _muted,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    rows[i].value,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 10,
                      color: _ink,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _metaLine(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(font: regular, fontSize: 9, color: _muted),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(font: bold, fontSize: 9, color: _ink),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kvRow(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: regular, fontSize: 9, color: _muted),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: bold, fontSize: 10, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _amountHighlight({
    required String label,
    required double amount,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _accent,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: regular,
              fontSize: 10,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            _currFmt.format(amount),
            style: pw.TextStyle(
              font: bold,
              fontSize: 14,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _itemsTable(
    List<Map<String, dynamic>> items,
    pw.Font regular,
    pw.Font bold,
  ) {
    final data = <List<String>>[];
    if (items.isEmpty) {
      data.add(['', 'No line items', '', '', '', '', '']);
    } else {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final qty = double.tryParse(item['qty'].toString()) ?? 0;
        final rate = double.tryParse(item['rate'].toString()) ?? 0;
        final gstPct = double.tryParse(item['gst'].toString()) ?? 0;
        final lineTotal = double.tryParse(item['amount'].toString()) ?? 0;
        final taxable = qty * rate;
        var gstAmt = double.tryParse(item['gstAmount']?.toString() ?? '') ?? 0;
        if (gstAmt <= 0 && gstPct > 0) {
          gstAmt = taxable * gstPct / 100;
        }
        // Amount = rate + GST (tax-inclusive). Prefer stored line total when inclusive.
        final inclusive = lineTotal >= taxable + gstAmt - 0.05 && lineTotal > 0
            ? lineTotal
            : taxable + gstAmt;
        if (gstAmt <= 0 && inclusive > taxable) {
          gstAmt = inclusive - taxable;
        }
        data.add([
          '${i + 1}',
        item['name'].toString(),
          qty == qty.roundToDouble()
              ? qty.toInt().toString()
              : qty.toStringAsFixed(2),
          _currFmt.format(rate),
          '${gstPct.toStringAsFixed(gstPct.truncateToDouble() == gstPct ? 0 : 1)}%',
          _currFmt.format(gstAmt),
          _currFmt.format(inclusive),
        ]);
      }
    }

    return _dataTable(
      headers: const [
        '#',
        'Item Description',
        'Qty',
        'Rate',
        'GST %',
        'GST Amt',
        'Amount',
      ],
      data: data,
      regular: regular,
      bold: bold,
      columnWidths: {
        0: const pw.FlexColumnWidth(0.55),
        1: const pw.FlexColumnWidth(3.4),
        2: const pw.FlexColumnWidth(0.85),
        3: const pw.FlexColumnWidth(1.45),
        4: const pw.FlexColumnWidth(0.95),
        5: const pw.FlexColumnWidth(1.45),
        6: const pw.FlexColumnWidth(1.55),
      },
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _dataTable({
    required List<String> headers,
    required List<List<String>> data,
    required pw.Font regular,
    required pw.Font bold,
    required Map<int, pw.TableColumnWidth> columnWidths,
    required Map<int, pw.Alignment> cellAlignments,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _line, width: 0.7),
      headerStyle:
          pw.TextStyle(font: bold, color: PdfColors.white, fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: _accent),
      cellStyle: pw.TextStyle(font: regular, fontSize: 8.5, color: _ink),
      oddRowDecoration: const pw.BoxDecoration(color: _soft),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      columnWidths: columnWidths,
      cellAlignments: cellAlignments,
    );
  }

  static pw.Widget _invoiceTotalsBlock({
    required double subtotal,
    required double discount,
    required double netAmount,
    required double gst,
    required double roundOff,
    required double total,
    required pw.Font regular,
    required pw.Font bold,
    String? notes,
    bool showBreakdown = false,
  }) {
    final wordsAndNotes = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Amount in Words',
          style: pw.TextStyle(
            font: bold,
            fontSize: 8,
            color: _muted,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _amountInWords(total),
          style: pw.TextStyle(
            font: regular,
            fontSize: 9,
            color: _ink,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        if (notes != null && notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Notes',
            style: pw.TextStyle(
              font: bold,
              fontSize: 8,
              color: _muted,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            notes.trim(),
            style: pw.TextStyle(font: regular, fontSize: 9, color: _ink),
          ),
        ],
      ],
    );

    if (!showBreakdown) {
      return wordsAndNotes;
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: wordsAndNotes),
        pw.SizedBox(width: 16),
        pw.Container(
          width: 230,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _line),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            children: [
              _totalRow('Subtotal', _currFmt.format(subtotal), regular, bold),
              if (discount > 0)
                _totalRow(
                    'Discount', _currFmt.format(discount), regular, bold),
              if (netAmount > 0 &&
                  (subtotal <= 0 || (netAmount - subtotal).abs() > 0.01))
                _totalRow(
                    'Net Amount', _currFmt.format(netAmount), regular, bold),
              if (gst > 0)
                _totalRow('GST', _currFmt.format(gst), regular, bold),
              if (roundOff != 0)
                _totalRow(
                    'Round Off', _currFmt.format(roundOff), regular, bold),
              pw.SizedBox(height: 6),
              pw.Container(height: 1, color: _line),
              pw.SizedBox(height: 6),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const pw.BoxDecoration(color: _accentSoft),
                child: _totalRow(
                  'Grand Total',
                  _currFmt.format(total),
                  regular,
                  bold,
                  isBold: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _statementTotals({
    required double openingBalance,
    required double totalDebits,
    required double totalCredits,
    required double closingBalance,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    String debitOf(double v) => v > 0.001 ? _plainAmt(v) : '';
    String creditOf(double v) => v < -0.001 ? _plainAmt(v) : '';

    pw.Widget row(String label, String debit, String credit, {bool emphasize = false}) {
      final style = pw.TextStyle(
        font: emphasize ? bold : regular,
        fontSize: emphasize ? 9.5 : 9,
        color: _ink,
      );
    return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: 8,
              child: pw.Text(label, style: style, textAlign: pw.TextAlign.right),
            ),
            pw.SizedBox(width: 10),
            pw.SizedBox(
              width: 70,
              child: pw.Text(debit, style: style, textAlign: pw.TextAlign.right),
            ),
            pw.SizedBox(width: 10),
            pw.SizedBox(
              width: 70,
              child:
                  pw.Text(credit, style: style, textAlign: pw.TextAlign.right),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          row(
            'Opening Balance',
            debitOf(openingBalance),
            creditOf(openingBalance),
          ),
          row(
            'Current Total',
            _plainAmt(totalDebits),
            _plainAmt(totalCredits),
            emphasize: true,
          ),
          pw.Container(height: 1, color: _line),
          row(
            'Closing Balance',
            debitOf(closingBalance),
            creditOf(closingBalance),
            emphasize: true,
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(
    pw.Font regular,
    pw.Font bold, {
    required String companyName,
  }) {
    pw.Widget box(String title) {
      return pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(height: 36),
            pw.Container(width: 140, height: 1, color: _line),
            pw.SizedBox(height: 6),
            pw.Text(
              title,
              style: pw.TextStyle(font: bold, fontSize: 9, color: _ink),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );
    }

    return pw.Column(
      children: [
        pw.Row(
          children: [
            box('Customer / Party Signature'),
            pw.SizedBox(width: 24),
            box('For $companyName'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Thank you for your business.',
          style: pw.TextStyle(font: regular, fontSize: 8, color: _muted),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  static pw.Widget _totalRow(
    String title,
    String value,
    pw.Font regular,
    pw.Font bold, {
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: isBold ? bold : regular,
                fontSize: isBold ? 10 : 9,
                color: isBold ? _ink : _muted,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: isBold ? bold : regular,
              fontSize: isBold ? 11 : 9,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  // ── Amount in words (INR) ─────────────────────────────────────────────────

  static String _amountInWords(double amount) {
    final rupees = amount.floor();
    final paise = ((amount - rupees) * 100).round();
    final words = _numberToWords(rupees);
    if (words.isEmpty) {
      return paise > 0
          ? 'Rupees Zero and ${_numberToWords(paise)} Paise Only'
          : 'Rupees Zero Only';
    }
    if (paise > 0) {
      return 'Rupees $words and ${_numberToWords(paise)} Paise Only';
    }
    return 'Rupees $words Only';
  }

  static String _numberToWords(int n) {
    if (n == 0) return 'Zero';
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];

    String twoDigits(int v) {
      if (v < 20) return ones[v];
      final t = tens[v ~/ 10];
      final o = ones[v % 10];
      return o.isEmpty ? t : '$t $o';
    }

    String threeDigits(int v) {
      final h = v ~/ 100;
      final r = v % 100;
      if (h == 0) return twoDigits(r);
      if (r == 0) return '${ones[h]} Hundred';
      return '${ones[h]} Hundred ${twoDigits(r)}';
    }

    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;

    if (crore > 0) parts.add('${threeDigits(crore)} Crore');
    if (lakh > 0) parts.add('${twoDigits(lakh)} Lakh');
    if (thousand > 0) parts.add('${twoDigits(thousand)} Thousand');
    if (n > 0) parts.add(threeDigits(n));
    return parts.join(' ');
  }

  // ── Delivery ──────────────────────────────────────────────────────────────

  static Future<void> _sharePdf(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Please find the attached PDF.',
        ),
      );
    }
  }

  static Future<void> _downloadPdf(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: filename,
    );
  }
}
