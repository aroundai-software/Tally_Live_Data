import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/supabase_service.dart';
import '../providers/company_provider.dart';
import 'ledger_statement_screen.dart';

class CustomerRankingScreen extends StatefulWidget {
  final List<Map<String, dynamic>> fastestCustomers;
  final List<Map<String, dynamic>> slowestCustomers;
  final bool initialIsFastest;

  const CustomerRankingScreen({
    super.key,
    required this.fastestCustomers,
    required this.slowestCustomers,
    required this.initialIsFastest,
  });

  @override
  State<CustomerRankingScreen> createState() => _CustomerRankingScreenState();
}

class _CustomerRankingScreenState extends State<CustomerRankingScreen> {
  late bool _isFastest;
  final SupabaseService _service = SupabaseService();

  @override
  void initState() {
    super.initState();
    _isFastest = widget.initialIsFastest;
  }

  Color _getHealthColor(double days) {
    if (days <= 7) return const Color(0xFF22C55E);
    if (days <= 20) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Future<void> _navigateToLedger(BuildContext context, String ledgerName) async {
    final companyName = CompanyProvider.of(context).selectedCompany;
    if (companyName == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
    );
    try {
      final ledgers = await _service.getLedgersByName(companyName: companyName, ledgerName: ledgerName);
      if (!context.mounted) return;
      Navigator.pop(context); // close loading
      if (ledgers.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => LedgerStatementScreen(ledger: ledgers.first),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find ledger: $ledgerName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isFastest ? '🏆 Fastest Paying Customers' : '⚠️ Slowest Paying Customers';
    final accentColor = _isFastest ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final customers = _isFastest ? widget.fastestCustomers : widget.slowestCustomers;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1A1F36))),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1F36)),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildToggleBtn('Fastest', true, const Color(0xFF22C55E)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildToggleBtn('Slowest', false, const Color(0xFFEF4444)),
                ),
              ],
            ),
          ),
          Expanded(
            child: customers.isEmpty
                ? const Center(child: Text('No customers found.'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final rank = index + 1;
                      final name = customer['ledger'] as String;
                      final avgDays = customer['avgDays'] as double;
                      final count = customer['count'] as int;
                      final color = _getHealthColor(avgDays);

                      return InkWell(
                        onTap: () => _navigateToLedger(context, name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text('#$rank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36))),
                                    const SizedBox(height: 4),
                                    Text('$count bills settled', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${avgDays.round()}d',
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String text, bool isFastestTarget, Color color) {
    final isSelected = _isFastest == isFastestTarget;
    return InkWell(
      onTap: () => setState(() => _isFastest = isFastestTarget),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          border: Border.all(color: isSelected ? color : Colors.grey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
