import 'package:flutter/material.dart';

class CompanyState extends ChangeNotifier {
  String? _selectedCompany;
  Map<String, bool> _enabledFeatures = {};

  int _syncTrigger = 0;
  int _companyRevision = 0;
  bool _featuresLoaded = false;
  bool get featuresLoaded => _featuresLoaded;

  String? get selectedCompany => _selectedCompany;
  Map<String, bool> get enabledFeatures => _enabledFeatures;
  int get syncTrigger => _syncTrigger;
  /// Increments whenever the selected company changes or is cleared.
  int get companyRevision => _companyRevision;

  bool isFeatureEnabled(String feature) {
    if (!_featuresLoaded) return false;
    bool enabled(String key) => _enabledFeatures[key] ?? true;
    if (!enabled(feature)) return false;
    final parent = feature.startsWith('stock_') ? 'stock'
      : feature.startsWith('out_') ? 'outstanding'
      : feature.startsWith('ls_') ? 'ledgers'
      : feature.startsWith('cf_') ? 'cash_flow'
      : feature.startsWith('rep_') ? 'analytics'
      : feature.startsWith('db_') ? 'dashboard' : null;
    if (parent != null && !enabled(parent)) return false;
    const dependencies = <String, List<String>>{
      'db_card_stock_value': ['stock', 'stock_cost'],
      'db_np_stock': ['stock', 'stock_cost'],
      'db_qa_stock': ['stock'],
      'db_card_today_sales': ['sales'],
      'db_qa_sales': ['sales'],
      'db_card_today_purchases': ['purchases'],
      'db_card_total_receivables': ['outstanding', 'out_receivables'],
      'db_card_overdue_receivables': ['outstanding', 'out_receivables'],
      'db_np_receivables': ['outstanding', 'out_receivables'],
      'db_card_total_payables': ['outstanding', 'out_payables'],
      'db_card_overdue_payables': ['outstanding', 'out_payables'],
      'db_np_payables': ['outstanding', 'out_payables'],
      'db_card_cash_bank': ['ledgers'],
      'db_np_cash': ['ledgers'],
      'db_np_bank': ['ledgers'],
      'db_qa_ledgers': ['ledgers'],
      'db_qa_reports': ['analytics'],
      'db_qa_balance_sheet': ['balance_sheet'],
      'db_qa_profit_loss': ['profit_loss'],
    };
    return (dependencies[feature] ?? const <String>[]).every(enabled);
  }

  void selectCompany(String company) {
    final trimmed = company.trim();
    if (trimmed.isEmpty) return;
    if (_selectedCompany != trimmed) {
      _enabledFeatures = {};
      _featuresLoaded = false;
      _companyRevision++;
    }
    _selectedCompany = trimmed;
    notifyListeners();
  }

  void setFeatures(Map<String, bool> features) {
    _enabledFeatures = Map<String, bool>.from(features);
    _featuresLoaded = true;
    notifyListeners();
  }

  void notifySyncCompleted() {
    _syncTrigger++;
    notifyListeners();
  }

  void clearCompany() {
    _featuresLoaded = false;
    _selectedCompany = null;
    _enabledFeatures = {};
    _syncTrigger = 0;
    _companyRevision++;
    notifyListeners();
  }
}

class CompanyProvider extends InheritedNotifier<CompanyState> {
  const CompanyProvider({
    super.key,
    required CompanyState state,
    required super.child,
  }) : super(notifier: state);

  static CompanyState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<CompanyProvider>();
    return provider!.notifier!;
  }

  static CompanyState? maybeOf(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<CompanyProvider>();
    return provider?.notifier;
  }
}
