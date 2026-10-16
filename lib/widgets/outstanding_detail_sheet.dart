import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/receivable_payable.dart';
import '../services/pdf_service.dart';
import 'summary_card.dart';

Future<void> showOutstandingDetailSheet({
  required BuildContext context,
  required OutstandingRecord record,
  required bool isReceivable,
}) {
  final accent =
      isReceivable ? AppTheme.receivableColor : AppTheme.payableColor;
  final dateFormat = DateFormat('dd MMM yyyy');
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
        .difference(DateTime(
            record.dueDate!.year, record.dueDate!.month, record.dueDate!.day))
        .inDays;
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.45,
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
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isReceivable
                                  ? Icons.call_received_rounded
                                  : Icons.call_made_rounded,
                              color: accent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.customerName,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                if (record.invoiceNumber.isNotEmpty)
                                  Text(
                                    'Bill ${record.invoiceNumber}',
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
                            color: accent,
                            tooltip: 'Share',
                            onPressed: () async {
                              try {
                                await PdfService.shareOutstandingBill(
                                  record: record,
                                  isReceivable: isReceivable,
                                );
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
                      _detailSection('Party Details', [
                        _detailItem(
                          isReceivable ? 'Customer' : 'Supplier',
                          record.customerName,
                        ),
                        if (record.groupName != null &&
                            record.groupName!.trim().isNotEmpty)
                          _detailItem('Group', record.groupName!.trim()),
                        if (record.mobile != null &&
                            record.mobile!.trim().isNotEmpty)
                          _detailItem(
                            'Phone',
                            record.mobile!.trim(),
                            onValueTap: () {
                              Clipboard.setData(
                                ClipboardData(text: record.mobile!.trim()),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Copied phone: ${record.mobile}'),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        if ((record.companyName ?? '').trim().isNotEmpty)
                          _detailItem('Company', record.companyName!.trim()),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Bill Details', [
                        if (record.invoiceNumber.isNotEmpty)
                          _detailItem('Bill No.', record.invoiceNumber),
                        if (record.billType != null &&
                            record.billType!.isNotEmpty)
                          _detailItem('Type', record.billType!),
                        if (record.date != null)
                          _detailItem(
                              'Bill Date', dateFormat.format(record.date!)),
                        if (record.dueDate != null)
                          _detailItem(
                              'Due Date', dateFormat.format(record.dueDate!)),
                        if (record.creditDays != null && record.creditDays! > 0)
                          _detailItem(
                              'Credit Days', '${record.creditDays}'),
                        _detailItem(
                          'Status',
                          isOverdue
                              ? (overdueDays > 0
                                  ? 'Overdue ${overdueDays}d'
                                  : 'Overdue')
                              : 'Current',
                          valueColor: isOverdue ? AppTheme.errorColor : null,
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Amount Details', [
                        if (record.openingBalance != 0)
                          _detailItem(
                            'Opening',
                            formatCurrency(record.openingBalance.abs()),
                          ),
                        if (record.closingBalance != 0)
                          _detailItem(
                            'Closing',
                            formatCurrency(record.closingBalance.abs()),
                          ),
                        if (record.amount != 0 &&
                            record.closingBalance == 0)
                          _detailItem(
                            'Amount',
                            formatCurrency(record.amount.abs()),
                          ),
                        _detailItem(
                          'Outstanding',
                          formatCurrency(displayAmount),
                          valueColor: isOverdue ? AppTheme.errorColor : accent,
                        ),
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

Widget _detailItem(
  String label,
  String value, {
  Color? valueColor,
  VoidCallback? onValueTap,
}) {
  final valueText = Text(
    value,
    textAlign: TextAlign.right,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: valueColor ?? AppTheme.textPrimary,
    ),
  );

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
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: onValueTap == null
              ? valueText
              : GestureDetector(onTap: onValueTap, child: valueText),
        ),
      ],
    ),
  );
}
