import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sales_invoice.dart';
import '../models/purchase_invoice.dart';

class PdfService {
  // ── Public entry points ──────────────────────────────────────────────────

  static Future<void> shareSalesInvoice(SalesInvoice invoice, List<InvoiceItem> items) async {
    final pdf = await _generateSalesPdf(invoice, items);
    await _sharePdf(pdf, 'Invoice_${invoice.invoiceNumber}.pdf');
  }

  static Future<void> downloadSalesInvoice(SalesInvoice invoice, List<InvoiceItem> items) async {
    final pdf = await _generateSalesPdf(invoice, items);
    await _downloadPdf(pdf, 'Invoice_${invoice.invoiceNumber}.pdf');
  }

  static Future<void> sharePurchaseInvoice(PurchaseInvoice invoice, List<PurchaseInvoiceItem> items) async {
    final pdf = await _generatePurchasePdf(invoice, items);
    await _sharePdf(pdf, 'Purchase_${invoice.invoiceNumber}.pdf');
  }

  static Future<void> downloadPurchaseInvoice(PurchaseInvoice invoice, List<PurchaseInvoiceItem> items) async {
    final pdf = await _generatePurchasePdf(invoice, items);
    await _downloadPdf(pdf, 'Purchase_${invoice.invoiceNumber}.pdf');
  }

  // ── PDF generators ────────────────────────────────────────────────────────

  static Future<pw.Document> _generateSalesPdf(SalesInvoice invoice, List<InvoiceItem> items) async {
    // Load Noto Sans for full Unicode support (₹ symbol, etc.)
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold    = await PdfGoogleFonts.notoSansBold();
    final theme   = pw.ThemeData.withFont(base: regular, bold: bold);

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          _buildHeader(invoice.companyName ?? 'Company', 'TAX INVOICE',
              invoice.invoiceNumber, invoice.invoiceDate, bold),
          pw.SizedBox(height: 20),
          _buildPartyDetails('Bill To:', invoice.customerName,
              invoice.shippingAddress, regular, bold),
          pw.SizedBox(height: 20),
          _buildItemsTable(
            items.map((e) => {
              'name': e.productName,
              'qty': e.quantity,
              'rate': e.unitPrice,
              'gst': e.gstRate,
              'amount': e.totalAmount,
            }).toList(),
            regular,
            bold,
          ),
          pw.SizedBox(height: 20),
          _buildTotals(invoice.totalAmount, invoice.discountAmount,
              invoice.gstAmount, invoice.netAmount, regular, bold),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _generatePurchasePdf(
      PurchaseInvoice invoice, List<PurchaseInvoiceItem> items) async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold    = await PdfGoogleFonts.notoSansBold();
    final theme   = pw.ThemeData.withFont(base: regular, bold: bold);

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          _buildHeader(invoice.companyName ?? 'Company', 'PURCHASE INVOICE',
              invoice.invoiceNumber, invoice.invoiceDate, bold),
          pw.SizedBox(height: 20),
          _buildPartyDetails('Vendor:', invoice.supplierName,
              invoice.shippingAddress, regular, bold),
          pw.SizedBox(height: 20),
          _buildItemsTable(
            items.map((e) => {
              'name': e.productName,
              'qty': e.quantity,
              'rate': e.unitPrice,
              'gst': e.gstRate,
              'amount': e.totalAmount,
            }).toList(),
            regular,
            bold,
          ),
          pw.SizedBox(height: 20),
          _buildTotals(invoice.totalAmount, invoice.discountAmount,
              invoice.gstAmount, invoice.netAmount, regular, bold),
        ],
      ),
    );
    return pdf;
  }

  // ── PDF layout widgets ────────────────────────────────────────────────────

  static pw.Widget _buildHeader(String companyName, String title,
      String invoiceNumber, DateTime? date, pw.Font bold) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(companyName,
                style: pw.TextStyle(font: bold, fontSize: 22)),
            pw.SizedBox(height: 4),
            pw.Text('Authorized Dealer',
                style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    font: bold, fontSize: 18, color: PdfColors.blue800)),
            pw.SizedBox(height: 6),
            pw.Text('Invoice #: $invoiceNumber',
                style: pw.TextStyle(font: bold, fontSize: 11)),
            if (date != null)
              pw.Text('Date: ${DateFormat('dd MMM yyyy').format(date)}',
                  style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPartyDetails(String label, String name,
      String? address, pw.Font regular, pw.Font bold) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: bold, fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.Text(name, style: pw.TextStyle(font: bold, fontSize: 13)),
          if (address != null && address.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(address,
                style: pw.TextStyle(font: regular, fontSize: 10)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildItemsTable(
      List<Map<String, dynamic>> items, pw.Font regular, pw.Font bold) {
    final headers = ['Item Description', 'Qty', 'Rate', 'GST %', 'Amount'];
    final currFmt = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);

    final data = items.map((item) {
      final rate   = double.tryParse(item['rate'].toString()) ?? 0;
      final amount = double.tryParse(item['amount'].toString()) ?? 0;
      return [
        item['name'].toString(),
        item['qty'].toString(),
        currFmt.format(rate),
        '${item['gst']}%',
        currFmt.format(amount),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(font: bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
      cellStyle: pw.TextStyle(font: regular),
      cellHeight: 28,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _buildTotals(double subtotal, double discount, double tax,
      double total, pw.Font regular, pw.Font bold) {
    final fmt = NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 220,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _totalRow('Subtotal:', fmt.format(subtotal), regular, bold),
              if (discount > 0)
                _totalRow('Discount:', fmt.format(discount), regular, bold),
              if (tax > 0) _totalRow('GST:', fmt.format(tax), regular, bold),
              pw.Divider(color: PdfColors.grey400),
              _totalRow('Total:', fmt.format(total), regular, bold,
                  isBold: true),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _totalRow(String title, String value, pw.Font regular,
      pw.Font bold, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  font: isBold ? bold : regular, fontSize: 11)),
          pw.Text(value,
              style: pw.TextStyle(
                  font: isBold ? bold : regular, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Delivery ──────────────────────────────────────────────────────────────

  /// Share via native share sheet (WhatsApp, Email, etc.)
  static Future<void> _sharePdf(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Please find the attached invoice.'),
      );
    }
  }

  /// Download: browser file download on web; saves to device on mobile via share sheet.
  static Future<void> _downloadPdf(pw.Document pdf, String filename) async {
    final bytes = await pdf.save();
    if (kIsWeb) {
      // Triggers an instant browser "Save As" download.
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      // Save to temp dir, then open native share sheet so the user can
      // choose "Save to Downloads" or open in a PDF viewer directly.
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: filename,
          text: 'Tap "Save to Files" or "Downloads" to keep this invoice.',
        ),
      );
    }
  }
}
