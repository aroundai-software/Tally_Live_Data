import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../models/purchase_invoice.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../services/pdf_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/summary_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/empty_state.dart';

class PurchaseInvoiceScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PurchaseInvoiceScreen({super.key, this.onBack});

  @override
  State<PurchaseInvoiceScreen> createState() => _PurchaseInvoiceScreenState();
}

class _PurchaseInvoiceScreenState extends State<PurchaseInvoiceScreen> {
  final SupabaseService _service = SupabaseService();
  List<PurchaseInvoice> _invoices = [];
  List<PurchaseInvoice> _filteredInvoices = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();

  // Search filter flags
  bool _searchInName = true;
  bool _searchInInvoice = true;
  bool _searchInAmount = true;
  bool _searchInDate = true;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredInvoices = _invoices);
      return;
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final monthFormat = DateFormat('MMMM');

    setState(() {
      _filteredInvoices = _invoices.where((inv) {
        final matchesName = _searchInName && inv.supplierName.toLowerCase().contains(query);
        final matchesInvoice = _searchInInvoice && inv.invoiceNumber.toLowerCase().contains(query);
        final matchesAmount = _searchInAmount && (
          inv.netAmount.toString().contains(query) || 
          inv.totalAmount.toString().contains(query)
        );
        
        bool matchesDate = false;
        if (_searchInDate && inv.invoiceDate != null) {
          final dateStr = dateFormat.format(inv.invoiceDate!).toLowerCase();
          final monthStr = monthFormat.format(inv.invoiceDate!).toLowerCase();
          matchesDate = dateStr.contains(query) || monthStr.contains(query);
        }

        return matchesName || matchesInvoice || matchesAmount || matchesDate;
      }).toList();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final items = await _service.getPurchaseInvoices(companyName: company);
      if (mounted) {
        setState(() { 
          _invoices = items; 
          _filteredInvoices = items;
          _isLoading = false; 
        });
        _onSearchChanged();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  double get _totalPurchases => _filteredInvoices.fold(0, (sum, inv) => sum + inv.netAmount);

  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Purchase Invoices'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primaryColor,
        child: Column(
          children: [
            _buildHeader(),
            SearchBarWidget(
              hintText: 'Search by name, invoice, date...',
              controller: _searchController,
              onChanged: (_) {}, // Handled by listener
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.tune_rounded, color: AppTheme.primaryColor),
                onSelected: (value) {
                  setState(() {
                    if (value == 'name') _searchInName = !_searchInName;
                    if (value == 'invoice') _searchInInvoice = !_searchInInvoice;
                    if (value == 'amount') _searchInAmount = !_searchInAmount;
                    if (value == 'date') _searchInDate = !_searchInDate;
                  });
                  _onSearchChanged();
                },
                itemBuilder: (context) => [
                  _buildFilterItem('supplier name', _searchInName, 'name'),
                  _buildFilterItem('Invoice Number', _searchInInvoice, 'invoice'),
                  _buildFilterItem('Amount', _searchInAmount, 'amount'),
                  _buildFilterItem('Date / Month', _searchInDate, 'date'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_isLoading) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF00BCD4), Color(0xFF00838F)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Purchases', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(formatCurrency(_totalPurchases), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text('${_filteredInvoices.length} invoices', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const ShimmerLoading(height: 120);
    if (_error != null) return ErrorState(message: _error!, onRetry: _loadData);
    if (_filteredInvoices.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No Purchase Invoices Found',
        subtitle: _searchController.text.isNotEmpty ? 'Try a different search term or check filters' : 'Purchases invoice data will appear here once synced from Tally',
        onRetry: _loadData,
      );
    }
    return AnimationLimiter(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _filteredInvoices.length,
        itemBuilder: (context, index) {
          final invoice = _filteredInvoices[index];
          return AnimationConfiguration.staggeredList(
            position: index,
            duration: const Duration(milliseconds: 350),
            child: SlideAnimation(verticalOffset: 30, child: FadeInAnimation(child: _InvoiceCard(invoice: invoice, onTap: () => _showInvoiceDetail(invoice)))),
          );
        },
      ),
    );
  }

  PopupMenuItem<String> _buildFilterItem(String label, bool isSelected, String value) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: isSelected ? AppTheme.primaryColor : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  void _showInvoiceDetail(PurchaseInvoice invoice) {
    final dateFormat = DateFormat('dd MMM yyyy');
    showModalBottomSheet(
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
              margin: const EdgeInsets.only(bottom: 36, left: 16, right: 16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppTheme.purchaseColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.receipt_long_rounded, color: AppTheme.purchaseColor, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Invoice #${invoice.invoiceNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
                                  if (invoice.invoiceDate != null)
                                    Text(dateFormat.format(invoice.invoiceDate!), style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share_rounded),
                              color: AppTheme.purchaseColor,
                              onPressed: () async {
                                try {
                                  final items = invoice.id != null ? await _service.getPurchaseInvoiceItems(invoice.id!) : <PurchaseInvoiceItem>[];
                                  await PdfService.sharePurchaseInvoice(invoice, items);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _detailSection('Supplier Details', [
                          _detailItem('Supplier', invoice.supplierName),
                          if (invoice.shippingAddress != null && invoice.shippingAddress!.isNotEmpty)
                            _detailItem('Ship To', invoice.shippingAddress!),
                          if (invoice.supplierCategoryName != null && invoice.supplierCategoryName!.isNotEmpty)
                            _detailItem('Category', invoice.supplierCategoryName!),
                          if (invoice.type != null && invoice.type!.isNotEmpty)
                            _detailItem('Type', invoice.type!),
                        ]),
                        const SizedBox(height: 16),
                        _detailSection('Amount Details', [
                          if (invoice.subtotalBeforeDiscount > 0)
                            _detailItem('Subtotal', formatCurrency(invoice.subtotalBeforeDiscount)),
                          if (invoice.discountAmount > 0)
                            _detailItem('Discount (${invoice.discountPercentage.toStringAsFixed(1)}%)', formatCurrency(invoice.discountAmount)),
                          _detailItem('Total Amount', formatCurrency(invoice.totalAmount)),
                          _detailItem('GST Amount', formatCurrency(invoice.gstAmount)),
                          _detailItem('Net Amount', formatCurrency(invoice.netAmount)),
                          if (invoice.roundOff != null && invoice.roundOff! != 0)
                            _detailItem('Round Off', formatCurrency(invoice.roundOff!)),
                        ]),
                        const SizedBox(height: 16),
                        _detailSection('Status', [
                          if (invoice.status != null) _detailItem('Status', invoice.status!),
                          _detailItem('Tally Synced', invoice.syncedToTally ? 'Yes' : 'No'),
                          if (invoice.remarks != null && invoice.remarks!.isNotEmpty)
                            _detailItem('Remarks', invoice.remarks!),
                        ]),
                        if (invoice.id != null) ...[
                          const SizedBox(height: 16),
                          FutureBuilder<List<PurchaseInvoiceItem>>(
                            future: _service.getPurchaseInvoiceItems(invoice.id!),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)));
                              }
                              if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                              return _buildItemsTable(snapshot.data!);
                            },
                          ),
                        ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  Widget _detailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)))),
      ]),
    );
  }

  Widget _buildItemsTable(List<PurchaseInvoiceItem> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1F36))),
        const SizedBox(height: 10),
        ...items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(child: Text(item.productName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)))),
                    Text(formatCurrency(item.totalAmount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.purchaseColor)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  _miniChip('Qty: ${item.quantity}'),
                  _miniChip('Rate: \u20B9${item.unitPrice.toStringAsFixed(2)}'),
                  _miniChip('GST: ${item.gstRate.toStringAsFixed(0)}%'),
                  if (item.freeQuantity > 0) _miniChip('Free: ${item.freeQuantity}'),
                  if (item.discountAmount > 0) _miniChip('Disc: \u20B9${item.discountAmount.toStringAsFixed(2)}'),
                ]),
              ]),
            )),
      ]),
    );
  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final PurchaseInvoice invoice;
  final VoidCallback? onTap;
  const _InvoiceCard({required this.invoice, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppTheme.purchaseColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.receipt_long_rounded, color: AppTheme.purchaseColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(invoice.supplierName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36))),
                    const SizedBox(height: 2),
                    Text('#${invoice.invoiceNumber}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatCurrency(invoice.netAmount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.purchaseColor)),
                    if (invoice.invoiceDate != null)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(dateFormat.format(invoice.invoiceDate!), style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (invoice.status != null) _statusChip(invoice.status!),
                const SizedBox(width: 8),
                if (invoice.type != null && invoice.type!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.purchaseColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text(invoice.type!, style: const TextStyle(fontSize: 11, color: AppTheme.purchaseColor, fontWeight: FontWeight.w600)),
                  ),
                const Spacer(),
                Icon(invoice.syncedToTally ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 16, color: invoice.syncedToTally ? Colors.green : Colors.grey.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'paid': color = Colors.green; break;
      case 'pending': color = Colors.orange; break;
      case 'cancelled': color = Colors.red; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}


