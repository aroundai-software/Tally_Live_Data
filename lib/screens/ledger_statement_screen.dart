import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/ledger.dart';
import '../models/daybook_entry.dart';
import '../services/supabase_service.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../widgets/ledger_performance_tab.dart';

class LedgerStatementScreen extends StatefulWidget {
  final Ledger ledger;

  const LedgerStatementScreen({super.key, required this.ledger});

  @override
  State<LedgerStatementScreen> createState() => _LedgerStatementScreenState();
}

class _LedgerStatementScreenState extends State<LedgerStatementScreen> {
  final _service = SupabaseService();
  bool _isLoading = true;
  String? _error;
  
  List<DaybookEntry> _transactions = [];
  double _openingBalance = 0.0;
  double _totalDebits = 0.0;
  double _totalCredits = 0.0;
  double _closingBalance = 0.0;

  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedVoucherType;
  Set<String> _availableVoucherTypes = {};
  
  bool _sortAscending = true;
  bool _isInit = false;
  bool _isListView = false;
  bool _isListViewInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isListViewInitialized) {
      // Default to list view on mobile screens (width < 800)
      _isListView = MediaQuery.of(context).size.width < 800;
      _isListViewInitialized = true;
    }
    if (!_isInit) {
      _loadData();
      _isInit = true;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final companyName = CompanyProvider.of(context).selectedCompany;
      
      final allTransactions = await _service.getLedgerVouchers(
        companyName: companyName ?? '',
        ledgerName: widget.ledger.name,
        endDate: null,
      );

      double runningBalance = widget.ledger.openingBalance;
      double openingForPeriod = runningBalance;
      double closingForPeriod = runningBalance;
      
      List<DaybookEntry> periodTransactions = [];
      double periodDebits = 0;
      double periodCredits = 0;

      _availableVoucherTypes.clear();

      for (var entry in allTransactions) {
        _availableVoucherTypes.add(entry.voucherType);

        if (_startDate != null && entry.date != null && entry.date!.isBefore(_startDate!)) {
          if (entry.isDebit) {
            openingForPeriod += entry.amount;
          } else {
            openingForPeriod -= entry.amount;
          }
        }
        
        if (_endDate == null || (entry.date != null && !entry.date!.isAfter(_endDate!))) {
          if (entry.isDebit) {
            closingForPeriod += entry.amount;
          } else {
            closingForPeriod -= entry.amount;
          }
        }

        bool isAfterStart = _startDate == null || (entry.date != null && !entry.date!.isBefore(_startDate!));
        bool isBeforeEnd = _endDate == null || (entry.date != null && !entry.date!.isAfter(_endDate!));

        if (isAfterStart && isBeforeEnd) {
          if (_selectedVoucherType == null || entry.voucherType == _selectedVoucherType) {
            periodTransactions.add(entry);
            if (entry.isDebit) {
              periodDebits += entry.amount;
            } else {
              periodCredits += entry.amount;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _openingBalance = openingForPeriod;
          _transactions = periodTransactions;
          _totalDebits = periodDebits;
          _totalCredits = periodCredits;
          _closingBalance = closingForPeriod;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null 
          ? DateTimeRange(start: _startDate!, end: _endDate!) 
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _loadData();
  }

  void _showVoucherTypeFilterDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Filter Voucher Type'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('All Voucher Types', style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () {
                    setState(() => _selectedVoucherType = null);
                    _loadData();
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
                ..._availableVoucherTypes.map((type) => ListTile(
                  title: Text(type),
                  onTap: () {
                    setState(() => _selectedVoucherType = type);
                    _loadData();
                    Navigator.pop(context);
                  },
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }

  String _formatAmount(double amount) {
    if (amount == 0) return '';
    return NumberFormat.currency(locale: 'en_IN', symbol: '\u20B9').format(amount.abs());
  }

  String _formatAmountPdf(double amount) {
    if (amount == 0) return '';
    final formatter = NumberFormat('#,##,##0.00', 'en_IN');
    return formatter.format(amount.abs());
  }

  Future<pw.Document> _generatePdfDocument() async {
    final pdf = pw.Document();

    final sortedTransactions = List<DaybookEntry>.from(_transactions)
      ..sort((a, b) {
        if (a.date == null || b.date == null) return 0;
        return a.date!.compareTo(b.date!);
      });

    String dateRangeText = '';
    if (_startDate != null && _endDate != null) {
      dateRangeText = '${DateFormat('d-MMM-yy').format(_startDate!)} to ${DateFormat('d-MMM-yy').format(_endDate!)}';
    } else {
      // Find range from actual transactions shown
      final validDates = sortedTransactions.where((e) => e.date != null).map((e) => e.date!).toList();
      if (validDates.isNotEmpty) {
        dateRangeText = '${DateFormat('d-MMM-yy').format(validDates.first)} to ${DateFormat('d-MMM-yy').format(validDates.last)}';
      } else {
        dateRangeText = '1-Apr-26 to 31-Mar-27'; // fallback
      }
    }

    final companyName = CompanyProvider.of(context).selectedCompany ?? 'Company Name';
    final address = companyName.contains('Kuncharakkattil') 
        ? 'Arumanoor P.O., Kottayam-686 564\nPh:0481-2541125, 2931125\n+91-9539065346'
        : '';

    final tableData = <List<String>>[];

    for (var entry in sortedTransactions) {
      String dateStr = entry.date != null ? DateFormat('dd-MMM-yy').format(entry.date!) : '';
      String prefix = entry.isDebit ? 'To ' : 'By ';
      String particulars = prefix + (entry.particulars ?? entry.ledgerName);
      String vchType = entry.voucherType;
      String vchNo = entry.voucherNumber ?? '';
      String debitStr = entry.isDebit ? _formatAmountPdf(entry.amount) : '';
      String creditStr = !entry.isDebit ? _formatAmountPdf(entry.amount) : '';
      
      tableData.add([dateStr, particulars, vchType, vchNo, debitStr, creditStr]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 10),
              pw.Text(widget.ledger.name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('Ledger Account', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 10),
              pw.Text(dateRangeText, style: const pw.TextStyle(fontSize: 10)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('Page ${context.pageNumber}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 5),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Particulars', 'Vch Type', 'Vch No.', 'Debit', 'Credit'],
              data: tableData,
              border: const pw.TableBorder(
                top: pw.BorderSide(width: 1),
                bottom: pw.BorderSide(width: 1),
                horizontalInside: pw.BorderSide.none,
                verticalInside: pw.BorderSide.none,
                left: pw.BorderSide.none,
                right: pw.BorderSide.none,
              ),
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 1)),
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(5),
                2: const pw.FlexColumnWidth(3),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
                5: const pw.FlexColumnWidth(2),
              },
            ),
            pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 1)),
              ),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                children: [
                  pw.Expanded(flex: 12, child: pw.SizedBox()),
                  pw.Expanded(
                    flex: 2, 
                    child: pw.Text(_formatAmountPdf(_totalDebits), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))
                  ),
                  pw.Expanded(
                    flex: 2, 
                    child: pw.Text(_formatAmountPdf(_totalCredits), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))
                  ),
                ]
              )
            )
          ];
        },
      ),
    );

    return pdf;
  }

  Future<void> _downloadPdf() async {
    try {
      final pdf = await _generatePdfDocument();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: '${widget.ledger.name}_Statement.pdf',
      );
    } catch (e, stack) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('PDF Error'),
            content: SingleChildScrollView(child: Text('$e\n$stack')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      final pdf = await _generatePdfDocument();
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: '${widget.ledger.name}_Statement.pdf',
      );
    } catch (e, stack) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Share Error'),
            content: SingleChildScrollView(child: Text('$e\n$stack')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  Widget _buildHeaderCell(String text, {int flex = 2, bool numeric = false, bool isSortable = false}) {
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: isSortable ? () {
          setState(() {
            _sortAscending = !_sortAscending;
          });
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              if (isSortable) ...[
                const SizedBox(width: 4),
                Icon(_sortAscending ? Icons.arrow_downward : Icons.arrow_upward, size: 14, color: Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataCell(String text, {int flex = 2, bool numeric = false, bool isBold = false, Color? textColor, double verticalPadding = 12}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: verticalPadding),
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: textColor ?? Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateRangeText = 'All Time';
    if (_startDate != null && _endDate != null) {
      dateRangeText = '${DateFormat('d-MMM-yy').format(_startDate!)} to ${DateFormat('d-MMM-yy').format(_endDate!)}';
    }

    final displayTransactions = _sortAscending ? _transactions : _transactions.reversed.toList();

    final companyState = CompanyProvider.of(context);
    final showTransactions = companyState.isFeatureEnabled('ls_transactions');
    final showPerformance = companyState.isFeatureEnabled('ls_performance');

    // Build the dynamic tab list
    final tabs = <Tab>[];
    final tabViews = <Widget>[];

    if (showTransactions) {
      tabs.add(const Tab(text: 'Transactions'));
      tabViews.add(Column(
        children: [
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_error!, style: const TextStyle(color: AppTheme.errorColor)),
            )))
          else
            Expanded(
              child: _isListView
                ? Column(
                    children: [
                      Expanded(
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(child: _buildContactDetails()),
                            SliverToBoxAdapter(child: _buildActiveFiltersBox()),
                            SliverPadding(
                              padding: const EdgeInsets.only(top: 8, bottom: 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildListCard(displayTransactions[index]),
                                  childCount: displayTransactions.length,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildMobileFooter(),
                    ],
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width < 800 ? 800 : MediaQuery.of(context).size.width,
                      child: Column(
                        children: [
                          Expanded(
                            child: CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(child: _buildContactDetails()),
                                SliverToBoxAdapter(child: _buildActiveFiltersBox()),
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _StickyHeaderDelegate(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        border: Border(bottom: BorderSide(color: Colors.grey.shade300))
                                      ),
                                      child: Row(
                                        children: [
                                          _buildHeaderCell('Date', flex: 2, isSortable: true),
                                          _buildHeaderCell('Particulars', flex: 4),
                                          _buildHeaderCell('Vch Type', flex: 2),
                                          _buildHeaderCell('Vch No.', flex: 2),
                                          _buildHeaderCell('Debit', flex: 2, numeric: true),
                                          _buildHeaderCell('Credit', flex: 2, numeric: true),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final entry = displayTransactions[index];
                                      return Container(
                                        decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                                        child: Row(
                                          children: [
                                            _buildDataCell(entry.date != null ? DateFormat('dd-MMM-yy').format(entry.date!) : '', flex: 2),
                                            _buildDataCell(entry.particulars ?? entry.ledgerName, flex: 4, isBold: true),
                                            _buildDataCell(entry.voucherType, flex: 2),
                                            _buildDataCell(entry.voucherNumber ?? '', flex: 2),
                                            _buildDataCell(entry.isDebit ? _formatAmount(entry.amount) : '', flex: 2, numeric: true),
                                            _buildDataCell(!entry.isDebit ? _formatAmount(entry.amount) : '', flex: 2, numeric: true),
                                          ],
                                        ),
                                      );
                                    },
                                    childCount: displayTransactions.length,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildTableFooter(),
                        ],
                      ),
                    ),
                  ),
            )
        ],
      ));
    }

    if (showPerformance) {
      tabs.add(const Tab(text: 'Performance'));
      tabViews.add(LedgerPerformanceTab(ledgerName: widget.ledger.name));
    }

    // Neither tab is enabled — show lock screen
    if (tabs.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(widget.ledger.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 48, color: Color(0xFF2453FF)),
              SizedBox(height: 12),
              Text('Feature Locked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              SizedBox(height: 8),
              Text('All tabs are disabled for this company.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7A94))),
            ],
          ),
        ),
      );
    }

    // Single tab — no tab bar needed
    if (tabs.length == 1) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(widget.ledger.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More Options',
              onSelected: (String result) {
                if (result == 'view_toggle') {
                  setState(() => _isListView = !_isListView);
                } else if (result == 'refresh') {
                  _loadData();
                } else if (result == 'date_range') {
                  _selectDateRange();
                } else if (result == 'clear_date') {
                  _clearDateRange();
                } else if (result == 'filter_voucher') {
                  _showVoucherTypeFilterDialog();
                } else if (result == 'sort') {
                  setState(() => _sortAscending = !_sortAscending);
                } else if (result == 'share') {
                  _sharePdf();
                } else if (result == 'download') {
                  _downloadPdf();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'view_toggle', child: Row(children: [Icon(_isListView ? Icons.table_chart_outlined : Icons.view_list_outlined, size: 20), const SizedBox(width: 12), Text(_isListView ? 'Table View' : 'List View')])),
                const PopupMenuItem<String>(value: 'refresh', child: Row(children: [Icon(Icons.refresh, size: 20), SizedBox(width: 12), Text('Refresh Data')])),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(value: 'date_range', child: Row(children: [Icon(Icons.calendar_month, size: 20), SizedBox(width: 12), Text('Filter by Date')])),
                if (_startDate != null || _endDate != null)
                  const PopupMenuItem<String>(value: 'clear_date', child: Row(children: [Icon(Icons.clear, size: 20, color: Colors.red), SizedBox(width: 12), Text('Clear Date Filter', style: TextStyle(color: Colors.red))])),
                const PopupMenuItem<String>(value: 'filter_voucher', child: Row(children: [Icon(Icons.filter_alt_outlined, size: 20), SizedBox(width: 12), Text('Filter Voucher Type')])),
                const PopupMenuDivider(),
                PopupMenuItem<String>(value: 'sort', child: Row(children: [const Icon(Icons.swap_vert, size: 20), const SizedBox(width: 12), Text(_sortAscending ? 'Sort Newest First' : 'Sort Oldest First')])),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(value: 'share', child: Row(children: [Icon(Icons.share, size: 20, color: AppTheme.primaryColor), SizedBox(width: 12), Text('Share via...')])),
                const PopupMenuItem<String>(value: 'download', child: Row(children: [Icon(Icons.download, size: 20, color: AppTheme.primaryColor), SizedBox(width: 12), Text('Save / Print')])),
              ],
            ),
          ],
        ),
        body: tabViews.first,
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
        title: Text(
          widget.ledger.name, 
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More Options',
            onSelected: (String result) {
              if (result == 'view_toggle') {
                setState(() => _isListView = !_isListView);
              } else if (result == 'refresh') {
                _loadData();
              } else if (result == 'date_range') {
                _selectDateRange();
              } else if (result == 'clear_date') {
                _clearDateRange();
              } else if (result == 'filter_voucher') {
                _showVoucherTypeFilterDialog();
              } else if (result == 'sort') {
                setState(() => _sortAscending = !_sortAscending);
              } else if (result == 'share') {
                _sharePdf();
              } else if (result == 'download') {
                _downloadPdf();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'view_toggle',
                child: Row(children: [Icon(_isListView ? Icons.table_chart_outlined : Icons.view_list_outlined, size: 20), const SizedBox(width: 12), Text(_isListView ? 'Table View' : 'List View')]),
              ),
              const PopupMenuItem<String>(value: 'refresh', child: Row(children: [Icon(Icons.refresh, size: 20), SizedBox(width: 12), Text('Refresh Data')])),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'date_range', child: Row(children: [Icon(Icons.calendar_month, size: 20), SizedBox(width: 12), Text('Filter by Date')])),
              if (_startDate != null || _endDate != null)
                const PopupMenuItem<String>(value: 'clear_date', child: Row(children: [Icon(Icons.clear, size: 20, color: Colors.red), SizedBox(width: 12), Text('Clear Date Filter', style: TextStyle(color: Colors.red))])),
              const PopupMenuItem<String>(value: 'filter_voucher', child: Row(children: [Icon(Icons.filter_alt_outlined, size: 20), SizedBox(width: 12), Text('Filter Voucher Type')])),
              const PopupMenuDivider(),
              PopupMenuItem<String>(value: 'sort', child: Row(children: [const Icon(Icons.swap_vert, size: 20), const SizedBox(width: 12), Text(_sortAscending ? 'Sort Newest First' : 'Sort Oldest First')])),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'share', child: Row(children: [Icon(Icons.share, size: 20, color: AppTheme.primaryColor), SizedBox(width: 12), Text('Share via...')])),
              const PopupMenuItem<String>(value: 'download', child: Row(children: [Icon(Icons.download, size: 20, color: AppTheme.primaryColor), SizedBox(width: 12), Text('Save / Print')])),
            ],
          ),
        ],
        bottom: TabBar(
          labelColor: AppTheme.primaryColor,
          indicatorColor: AppTheme.primaryColor,
          tabs: tabs,
        ),
      ),
      body: TabBarView(children: tabViews),
      ),
    );
  }

  Widget _buildContactDetails() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if (widget.ledger.gstNumber != null && widget.ledger.gstNumber!.isNotEmpty)
                Text('GSTIN: ${widget.ledger.gstNumber}', style: const TextStyle(fontSize: 12)),
              if (widget.ledger.phone != null && widget.ledger.phone!.isNotEmpty)
                Text('Mob: ${widget.ledger.phone}', style: const TextStyle(fontSize: 12)),
              if (widget.ledger.email != null && widget.ledger.email!.isNotEmpty)
                Text('Email: ${widget.ledger.email}', style: const TextStyle(fontSize: 12)),
            ],
          ),
          if (widget.ledger.fullAddress.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Addr: ${widget.ledger.fullAddress}', style: const TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis), maxLines: 1)),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersBox() {
    if (_startDate == null && _endDate == null && _selectedVoucherType == null) {
      return const SizedBox.shrink();
    }

    String dateText = '';
    if (_startDate != null && _endDate != null) {
      dateText = '${DateFormat('d-MMM-yy').format(_startDate!)} to ${DateFormat('d-MMM-yy').format(_endDate!)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (dateText.isNotEmpty)
            InputChip(
              label: Text(dateText, style: const TextStyle(fontSize: 12)),
              onDeleted: _clearDateRange,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
              deleteIconColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
              visualDensity: VisualDensity.compact,
            ),
          if (_selectedVoucherType != null)
            InputChip(
              label: Text(_selectedVoucherType!, style: const TextStyle(fontSize: 12)),
              onDeleted: () {
                setState(() => _selectedVoucherType = null);
                _loadData();
              },
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
              deleteIconColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildListCard(DaybookEntry entry) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.date != null ? DateFormat('dd-MMM-yy').format(entry.date!) : '',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.voucherType,
                  style: const TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.particulars ?? entry.ledgerName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (entry.voucherNumber != null && entry.voucherNumber!.isNotEmpty)
             Padding(
               padding: const EdgeInsets.only(top: 4),
               child: Text('Ref: ${entry.voucherNumber}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
             ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                entry.isDebit ? 'DEBIT' : 'CREDIT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: entry.isDebit ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
              Text(
                _formatAmount(entry.amount),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: entry.isDebit ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 4)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Opening Balance', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(_formatAmount(_openingBalance), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Current Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text('Dr ${_formatAmount(_totalDebits)}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 8),
                    Text('Cr ${_formatAmount(_totalCredits)}', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Closing Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(_formatAmount(_closingBalance), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableFooter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -4), blurRadius: 4)
        ]
      ),
      child: Column(
        children: [
          // Opening Balance Row
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
            child: Row(
              children: [
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell('Opening Balance', flex: 4, isBold: true, textColor: Colors.grey, verticalPadding: 6),
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell(_openingBalance > 0 ? _formatAmount(_openingBalance) : '', flex: 2, numeric: true, isBold: true, verticalPadding: 6),
                _buildDataCell(_openingBalance < 0 ? _formatAmount(_openingBalance) : '', flex: 2, numeric: true, isBold: true, verticalPadding: 6),
              ],
            ),
          ),
          // Current Total Row
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
            child: Row(
              children: [
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell('Current Total', flex: 4, isBold: true, verticalPadding: 6),
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell(_formatAmount(_totalDebits), flex: 2, numeric: true, isBold: true, verticalPadding: 6),
                _buildDataCell(_formatAmount(_totalCredits), flex: 2, numeric: true, isBold: true, verticalPadding: 6),
              ],
            ),
          ),
          // Closing Balance Row
          Container(
            decoration: const BoxDecoration(color: Colors.white),
            child: Row(
              children: [
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell('Closing Balance', flex: 4, isBold: true, verticalPadding: 6),
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell('', flex: 2, verticalPadding: 6),
                _buildDataCell(_closingBalance > 0 ? _formatAmount(_closingBalance) : '', flex: 2, numeric: true, isBold: true, verticalPadding: 6),
                _buildDataCell(_closingBalance < 0 ? _formatAmount(_closingBalance) : '', flex: 2, numeric: true, isBold: true, verticalPadding: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StickyHeaderDelegate({required this.child, this.height = 46.0});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}
