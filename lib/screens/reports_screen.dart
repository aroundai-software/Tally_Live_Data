import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/shimmer_loading.dart';

// ---------------------------------------------------------------------------
// Design tokens (mirrors the HTML demo palette)
// ---------------------------------------------------------------------------
class _Palette {
  static const ink900 = Color(0xFF0F1A2B);
  static const ink700 = Color(0xFF3A4A63);
  static const ink500 = Color(0xFF6B7A94);
  static const line = Color(0xFFE4E9F1);
  static const paper = Color(0xFFF5F7FB);
  static const blue = Color(0xFF2453FF);
  static const blueSoft = Color(0xFFE9EEFF);
  static const teal = Color(0xFF0DA6A0);
  static const tealSoft = Color(0xFFE1F5F3);
  static const amber = Color(0xFFB96A00);
  static const amberSoft = Color(0xFFFBEEDC);
  static const red = Color(0xFFC2372A);
  static const redSoft = Color(0xFFFBEAE8);
}

// Cutoff options available for the "unused" filters.
const List<int> _kCutoffOptions = [30, 90, 180, 365];

class ReportsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const ReportsScreen({super.key, this.onBack});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseService _service = SupabaseService();
  bool _isLoading = true;

  List<Map<String, dynamic>> _profitData = [];
  List<Map<String, dynamic>> _fastItems = [];
  List<Map<String, dynamic>> _slowItems = [];
  List<Map<String, dynamic>> _unusedLedgers = [];
  List<Map<String, dynamic>> _unusedItems = [];

  // User-adjustable "no activity in X days" cutoffs — independent per section,
  // since a quiet customer and slow-moving equipment stock aren't the same
  // business question.
  int _ledgerCutoffDays = 180;
  int _itemCutoffDays = 180;
  int _velocityCutoffDays = 30;
  String _velocityFilter = 'fast';
  String _dormantFilter = 'ledgers';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final company = CompanyProvider.of(context).selectedCompany;
      final results = await Future.wait([
        _service.getDailyProfit(companyName: company, days: 14),
        _service.getFastMovingItems(companyName: company, days: _velocityCutoffDays),
        _service.getSlowMovingItems(companyName: company, days: _velocityCutoffDays),
        _service.getUnusedLedgers(companyName: company, days: _ledgerCutoffDays),
        _service.getUnusedItems(companyName: company, days: _itemCutoffDays),
      ]);

      if (mounted) {
        setState(() {
          _profitData = (results[0] as List).cast<Map<String, dynamic>>();
          _fastItems = (results[1] as List).cast<Map<String, dynamic>>();
          _slowItems = (results[2] as List).cast<Map<String, dynamic>>();
          _unusedLedgers = (results[3] as List).cast<Map<String, dynamic>>();
          _unusedItems = (results[4] as List).cast<Map<String, dynamic>>();

          _isLoading = false;
        });
      }
    } catch (e, st) {
      print('Error loading data: $e');
      print(st);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Re-fetches only the unused-ledgers section with a new cutoff.
  Future<void> _reloadLedgers(int cutoffDays) async {
    setState(() => _ledgerCutoffDays = cutoffDays);
    final company = CompanyProvider.of(context).selectedCompany;
    final res = await _service.getUnusedLedgers(companyName: company, days: cutoffDays);
    if (mounted) setState(() => _unusedLedgers = (res as List).cast<Map<String, dynamic>>());
  }

  // Re-fetches only the unused-items section with a new cutoff.
  Future<void> _reloadItems(int cutoffDays) async {
    setState(() => _itemCutoffDays = cutoffDays);
    final company = CompanyProvider.of(context).selectedCompany;
    final res = await _service.getUnusedItems(companyName: company, days: cutoffDays);
    if (mounted) setState(() => _unusedItems = (res as List).cast<Map<String, dynamic>>());
  }

  // Re-fetches only the velocity sections with a new cutoff.
  Future<void> _reloadVelocity(int cutoffDays) async {
    setState(() => _velocityCutoffDays = cutoffDays);
    final company = CompanyProvider.of(context).selectedCompany;
    final res = await Future.wait([
      _service.getFastMovingItems(companyName: company, days: cutoffDays),
      _service.getSlowMovingItems(companyName: company, days: cutoffDays),
    ]);
    if (mounted) {
      setState(() {
        _fastItems = (res[0] as List).cast<Map<String, dynamic>>();
        _slowItems = (res[1] as List).cast<Map<String, dynamic>>();
      });
    }
  }

  // ---------------------------------------------------------------------
  // Derived KPI numbers
  // ---------------------------------------------------------------------
  double get _totalRevenue => _profitData.fold(
      0.0, (s, d) => s + (double.tryParse(d['total_revenue']?.toString() ?? '0') ?? 0));

  double get _totalProfit => _profitData.fold(
      0.0, (s, d) => s + (double.tryParse(d['estimated_profit']?.toString() ?? '0') ?? 0));

  double get _deadStockValue => _unusedItems.fold(
      0.0, (s, d) => s + (double.tryParse(d['stock_value']?.toString() ?? '0') ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadData),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _Palette.blue,
          unselectedLabelColor: _Palette.ink500,
          indicatorColor: _Palette.blue,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Velocity'),
            Tab(text: 'Dormant'),
          ],
        ),
      ),
      body: _isLoading
          ? const ShimmerGridLoading(itemCount: 5)
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: OVERVIEW & PROFIT
                RefreshIndicator(
                  onRefresh: _loadData,
                  color: _Palette.blue,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 720;
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          _buildKpiRow(isWide),
                          const SizedBox(height: 20),
                          _sectionCard(
                            title: 'Sales & Profit — Daily',
                            tag: const _SectionTag(label: '14 day trend', color: _Palette.blue, bg: _Palette.blueSoft),
                            child: _buildProfitChart(),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // TAB 2: VELOCITY
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Fast Moving'),
                                selected: _velocityFilter == 'fast',
                                onSelected: (_) => setState(() => _velocityFilter = 'fast'),
                                selectedColor: _Palette.teal,
                                backgroundColor: _Palette.paper,
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _velocityFilter == 'fast' ? Colors.white : _Palette.ink700,
                                ),
                                side: const BorderSide(color: _Palette.line),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Slow Moving'),
                                selected: _velocityFilter != 'fast',
                                onSelected: (_) => setState(() => _velocityFilter = 'slow'),
                                selectedColor: _Palette.amber,
                                backgroundColor: _Palette.paper,
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _velocityFilter != 'fast' ? Colors.white : _Palette.ink700,
                                ),
                                side: const BorderSide(color: _Palette.line),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _cutoffChips(_velocityCutoffDays, _reloadVelocity),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadData,
                        color: _Palette.blue,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 720;
                            final isFast = _velocityFilter == 'fast';
                            final currentList = isFast ? _fastItems : _slowItems;
                            return CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.all(16),
                                  sliver: SliverToBoxAdapter(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: _sectionCard(
                                        key: ValueKey('velocity_chart_${_velocityFilter}_$_velocityCutoffDays'),
                                        title: isFast ? 'Fast Moving Distribution' : 'Slow Moving Distribution',
                                        tag: _SectionTag(
                                          label: 'Top 7 threshold',
                                          color: isFast ? _Palette.teal : _Palette.amber,
                                          bg: isFast ? _Palette.tealSoft : _Palette.amberSoft,
                                        ),
                                        child: _buildVelocityChart(isWide, isFast),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  sliver: SliverList.builder(
                                    itemCount: currentList.isEmpty ? 2 : currentList.length + 2,
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                            border: Border(
                                              top: BorderSide(color: _Palette.line),
                                              left: BorderSide(color: _Palette.line),
                                              right: BorderSide(color: _Palette.line),
                                            ),
                                          ),
                                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(child: Text(isFast ? 'All Fast Moving Items' : 'All Slow Moving Items', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink900))),
                                                  _SectionTag(label: 'All filtered items', color: isFast ? _Palette.teal : _Palette.amber, bg: isFast ? _Palette.tealSoft : _Palette.amberSoft),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              if (currentList.isNotEmpty) ...[
                                                Row(
                                                  children: [
                                                    const Expanded(flex: 3, child: Text('Item', style: _headerStyle)),
                                                    Expanded(flex: 1, child: Text('Qty sold', textAlign: TextAlign.right, style: _headerStyle)),
                                                    if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
                                                  ],
                                                ),
                                                const Divider(height: 18, color: _Palette.line),
                                              ]
                                            ],
                                          ),
                                        );
                                      }
                                      if (index == (currentList.isEmpty ? 1 : currentList.length + 1)) {
                                        return Container(
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                                            border: Border(
                                              bottom: BorderSide(color: _Palette.line),
                                              left: BorderSide(color: _Palette.line),
                                              right: BorderSide(color: _Palette.line),
                                            ),
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
                                          ),
                                          child: currentList.isEmpty ? Center(child: Text('No items found for this filter.', style: const TextStyle(color: _Palette.ink500, fontSize: 13))) : null,
                                        );
                                      }
                                      final item = currentList[index - 1];
                                      return Container(
                                        color: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            border: Border(left: BorderSide(color: _Palette.line), right: BorderSide(color: _Palette.line)),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(item['product_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Text('${item['total_sold']}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, color: _Palette.ink700, fontSize: 13)),
                                              ),
                                              if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                // TAB 3: DORMANT
                Padding(
                  padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Unused Ledgers'),
                            selected: _dormantFilter == 'ledgers',
                            onSelected: (_) => setState(() => _dormantFilter = 'ledgers'),
                            selectedColor: _Palette.blue,
                            backgroundColor: _Palette.paper,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _dormantFilter == 'ledgers' ? Colors.white : _Palette.ink700,
                            ),
                            side: const BorderSide(color: _Palette.line),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Unused Items'),
                            selected: _dormantFilter == 'items',
                            onSelected: (_) => setState(() => _dormantFilter = 'items'),
                            selectedColor: _Palette.red,
                            backgroundColor: _Palette.paper,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _dormantFilter == 'items' ? Colors.white : _Palette.ink700,
                            ),
                            side: const BorderSide(color: _Palette.line),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _dormantFilter == 'ledgers'
                              ? _sectionCard(
                                  key: ValueKey('dormant_ledgers_$_ledgerCutoffDays'),
                                  title: 'Unused Ledgers (${_unusedLedgers.length})',
                                  tag: const _SectionTag(label: 'No activity', color: _Palette.blue, bg: _Palette.blueSoft),
                                  expanded: true,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _cutoffChips(_ledgerCutoffDays, _reloadLedgers),
                                      const SizedBox(height: 12),
                                      Expanded(child: _buildLedgersTable()),
                                    ],
                                  ),
                                )
                              : _sectionCard(
                                  key: ValueKey('dormant_items_$_itemCutoffDays'),
                                  title: 'Unused Items (${_unusedItems.length})',
                                  tag: const _SectionTag(label: 'In stock, no sale', color: _Palette.red, bg: _Palette.redSoft),
                                  expanded: true,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _cutoffChips(_itemCutoffDays, _reloadItems),
                                      const SizedBox(height: 12),
                                      Expanded(child: _buildItemsTable()),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------
  // KPI row
  // ---------------------------------------------------------------------
  Widget _buildKpiRow(bool isWide) {
    final currency = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
    final cards = [
      _KpiCard(label: 'Gross revenue', value: currency.format(_totalRevenue)),
      _KpiCard(label: 'Est. gross profit', value: currency.format(_totalProfit)),
      _KpiCard(label: 'Dead stock value', value: currency.format(_deadStockValue)),
      _KpiCard(label: 'Unused ledgers', value: '${_unusedLedgers.length}'),
      _KpiCard(label: 'Unused items', value: '${_unusedItems.length}'),
    ];
    final columns = isWide ? 5 : 2;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: isWide ? 1.5 : 1.6,
      children: cards,
    );
  }

  // ---------------------------------------------------------------------
  // Sales & Profit Daily chart
  // ---------------------------------------------------------------------
  Widget _buildProfitChart() {
    if (_profitData.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('Not enough data to compute profit trend.', style: TextStyle(color: _Palette.ink500))),
      );
    }
    final chartData = _profitData.reversed.toList();
    double maxRev = 0;
    for (var d in chartData) {
      final rev = double.tryParse(d['total_revenue']?.toString() ?? '0') ?? 0;
      if (rev > maxRev) maxRev = rev;
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxRev > 0 ? maxRev * 1.2 : 100,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => const Color(0xFF1E293B),
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  tooltipMargin: 8,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (rodIndex != 0) return null; // Only show one combined tooltip per group
                    
                    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
                    final rev = group.barRods.isNotEmpty ? group.barRods[0].toY : 0;
                    final prof = group.barRods.length > 1 ? group.barRods[1].toY : 0;
                    
                    return BarTooltipItem(
                      'Rev : ${currency.format(rev)} \n',
                      const TextStyle(
                        color: _Palette.blue,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      children: [
                        TextSpan(
                          text: 'Profit : ${currency.format(prof)}',
                          style: const TextStyle(
                            color: _Palette.teal,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() >= 0 && value.toInt() < chartData.length) {
                        final dateStr = chartData[value.toInt()]['sale_date'].toString();
                        final date = DateTime.tryParse(dateStr);
                        if (date != null) {
                          final isToday = value.toInt() == chartData.length - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              isToday ? 'Today' : DateFormat('dd/MM').format(date),
                              style: TextStyle(
                                fontSize: 10,
                                color: isToday ? _Palette.ink900 : _Palette.ink500,
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          );
                        }
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const Text('');
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: Text(
                          NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹').format(value),
                          style: const TextStyle(fontSize: 10, color: _Palette.ink500),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => const FlLine(color: _Palette.line, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(chartData.length, (i) {
                final rev = double.tryParse(chartData[i]['total_revenue']?.toString() ?? '0') ?? 0;
                final prof = double.tryParse(chartData[i]['estimated_profit']?.toString() ?? '0') ?? 0;
                final isToday = i == chartData.length - 1;
                
                return BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: rev,
                    color: isToday ? _Palette.blue : _Palette.blue.withValues(alpha: 0.3),
                    width: 8,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  BarChartRodData(
                    toY: prof,
                    color: isToday ? _Palette.teal : _Palette.teal.withValues(alpha: 0.3),
                    width: 8,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]);
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          children: const [
            _LegendItem(color: _Palette.blue, label: 'Gross revenue'),
            _LegendItem(color: _Palette.teal, label: 'Est. gross profit'),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Velocity Chart: donut with center total + table for Top 7
  // ---------------------------------------------------------------------
  Widget _buildVelocityChart(bool isWide, bool isFast) {
    final list = isFast ? _fastItems : _slowItems;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No sales recorded in this period.', style: TextStyle(color: _Palette.ink500))),
      );
    }
    final colors = [_Palette.blue, _Palette.teal, _Palette.amber, const Color(0xFF7B5CFA), _Palette.red, Colors.pink, Colors.lime];
    final top7 = list.take(7).toList();
    final total = top7.fold<double>(0, (s, d) => s + (double.tryParse(d['total_sold'].toString()) ?? 0));

    final donut = SizedBox(
      height: 170,
      width: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 46,
              sections: total == 0
                  ? [PieChartSectionData(color: _Palette.line, value: 1, title: '', radius: 26)]
                  : List.generate(top7.length, (i) {
                      final val = double.tryParse(top7[i]['total_sold'].toString()) ?? 0;
                      return PieChartSectionData(color: colors[i % colors.length], value: val, title: '', radius: 26);
                    }),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(total.toStringAsFixed(0),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _Palette.ink900)),
              const Text('units sold', style: TextStyle(fontSize: 11, color: _Palette.ink500)),
            ],
          ),
        ],
      ),
    );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(top7.length, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
              Expanded(
                child: Text(top7[i]['product_name'] ?? 'Unknown',
                    style: const TextStyle(fontSize: 13, color: _Palette.ink900, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text('${top7[i]['total_sold']}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _Palette.ink900)),
              if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
            ],
          ),
        );
      }),
    );

    if (isWide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        donut,
        const SizedBox(width: 24),
        Expanded(child: table),
      ]);
    }
    return Column(children: [
      Center(child: donut),
      const SizedBox(height: 14),
      table,
    ]);
  }

  // ---------------------------------------------------------------------
  // Generic simple table (used for Slow Moving)
  // ---------------------------------------------------------------------
  Widget _buildSimpleTable({
    required List<Map<String, dynamic>> data,
    required String emptyMessage,
    required String valueKey,
    required String valueLabel,
    bool isWide = true,
  }) {
    if (data.isEmpty) {
      return _emptyState(emptyMessage);
    }
    return Column(
      children: [
        Row(
          children: [
            const Expanded(flex: 3, child: Text('Item', style: _headerStyle)),
            Expanded(flex: 1, child: Text(valueLabel, textAlign: TextAlign.right, style: _headerStyle)),
            if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
          ],
        ),
        const Divider(height: 18, color: _Palette.line),
        ...data.map((item) {
          return RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(item['product_name'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('${item[valueKey]}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: _Palette.ink700, fontSize: 13)),
                  ),
                  if (isWide) const SizedBox(width: 80) else const SizedBox(width: 12),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Unused Ledgers table
  // ---------------------------------------------------------------------
  Widget _buildLedgersTable() {
    if (_unusedLedgers.isEmpty) {
      return _emptyState('No ledgers idle for $_ledgerCutoffDays+ days.');
    }
    return Column(
      children: [
        Row(
          children: const [
            Expanded(flex: 2, child: Text('Customer', style: _headerStyle)),
            Expanded(flex: 1, child: Text('Phone', textAlign: TextAlign.right, style: _headerStyle)),
          ],
        ),
        const Divider(height: 18, color: _Palette.line),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: _Palette.blue,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _unusedLedgers.length,
              itemBuilder: (context, index) {
              final item = _unusedLedgers[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(item['customer_name'] ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(item['mobile_number']?.toString() ?? item['phone']?.toString() ?? '-',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink500, fontSize: 13)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Unused Items table
  // ---------------------------------------------------------------------
  Widget _buildItemsTable() {
    if (_unusedItems.isEmpty) {
      return _emptyState('No items idle for $_itemCutoffDays+ days.');
    }
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Column(
      children: [
        Row(
          children: const [
            Expanded(flex: 3, child: Text('Product', style: _headerStyle)),
            Expanded(flex: 1, child: Text('Qty', textAlign: TextAlign.right, style: _headerStyle)),
            Expanded(flex: 2, child: Text('Stock value', textAlign: TextAlign.right, style: _headerStyle)),
          ],
        ),
        const Divider(height: 18, color: _Palette.line),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: _Palette.blue,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _unusedItems.length,
              itemBuilder: (context, index) {
              final item = _unusedItems[index];
              final val = double.tryParse(item['stock_value']?.toString() ?? '0') ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(item['product_name'] ?? '-',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: _Palette.ink900, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text('${item['quantity']}', textAlign: TextAlign.right, style: const TextStyle(color: _Palette.ink500, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(currency.format(val),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: _Palette.red, fontSize: 13)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Shared bits
  // ---------------------------------------------------------------------
  Widget _cutoffChips(int selected, void Function(int) onSelect) {
    return Wrap(
      spacing: 6,
      children: _kCutoffOptions.map((d) {
        final isSelected = d == selected;
        return ChoiceChip(
          label: Text('${d}d'),
          selected: isSelected,
          onSelected: (_) => onSelect(d),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : _Palette.ink700,
          ),
          selectedColor: _Palette.blue,
          backgroundColor: _Palette.paper,
          side: const BorderSide(color: _Palette.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      }).toList(),
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(message, style: const TextStyle(color: _Palette.ink500, fontSize: 13), textAlign: TextAlign.center),
      ),
    );
  }

  Widget _sectionCard({Key? key, required String title, required Widget tag, required Widget child, bool expanded = false}) {
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _Palette.ink900)),
            ),
            tag,
          ],
        ),
        const SizedBox(height: 14),
        expanded ? Expanded(child: child) : child,
      ],
    );

    return RepaintBoundary(
      child: Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Palette.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: content,
      ),
    );
  }
}

const TextStyle _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: _Palette.ink500,
  letterSpacing: 0.3,
);

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  const _KpiCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _Palette.ink500, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _Palette.ink900)),
          ),
        ],
      ),
    );
  }
}

class _SectionTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _SectionTag({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _StatusBadge({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Palette.ink900)),
      ],
    );
  }
}