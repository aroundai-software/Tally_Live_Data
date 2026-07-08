import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import 'company_selection_screen.dart';
import 'dashboard_screen.dart';
import 'stock_screen.dart';
import 'ledger_screen.dart';
import 'receivables_payables_screen.dart';
import 'sales_invoice_screen.dart';
import 'purchase_invoices_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void _onNavigate(int index) {
    setState(() => _currentIndex = index);
  }

  void _switchCompany() {
    CompanyProvider.of(context).clearCompany();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CompanySelectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companyName = CompanyProvider.of(context).selectedCompany ?? '';
    final screens = [
      DashboardScreen(onNavigate: _onNavigate),
      StockScreen(onBack: () => _onNavigate(0)),
      LedgerScreen(onBack: () => _onNavigate(0)),
      ReceivablesPayablesScreen(onBack: () => _onNavigate(0)),
      SalesInvoiceScreen(onBack: () => _onNavigate(0)),
      PurchaseInvoiceScreen(onBack: () => _onNavigate(0)),
    ];

    return Scaffold(
      body: Column(
        children: [
          _CompanyBanner(companyName: companyName, onSwitch: _switchCompany),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(
                index: _currentIndex,
                children: screens,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isSelected: _currentIndex == 0,
                  onTap: () => _onNavigate(0),
                  color: AppTheme.primaryColor,
                ),
                _NavItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Stock',
                  isSelected: _currentIndex == 1,
                  onTap: () => _onNavigate(1),
                  color: AppTheme.stockColor,
                ),
                _NavItem(
                  icon: Icons.people_alt_rounded,
                  label: 'Ledgers',
                  isSelected: _currentIndex == 2,
                  onTap: () => _onNavigate(2),
                  color: AppTheme.primaryColor,
                ),
                _NavItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Recv/Pay',
                  isSelected: _currentIndex == 3,
                  onTap: () => _onNavigate(3),
                  color: AppTheme.receivableColor,
                ),
                _NavItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Sales',
                  isSelected: _currentIndex == 4,
                  onTap: () => _onNavigate(4),
                  color: AppTheme.salesColor,
                ),
                _NavItem(
                  icon: Icons.shopping_cart_rounded,
                  label: 'Purchases',
                  isSelected: _currentIndex == 5,
                  onTap: () => _onNavigate(5),
                  color: AppTheme.purchaseColor ?? Colors.purple, // Assuming AppTheme has purchaseColor, if not fallback to purple
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? color : Colors.grey.shade400,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ));
  }
}

class _CompanyBanner extends StatelessWidget {
  final String companyName;
  final VoidCallback onSwitch;
  const _CompanyBanner({required this.companyName, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D47A1),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.monitor_heart_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  companyName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: onSwitch,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 16),
                      SizedBox(width: 4),
                      Text('Switch', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
