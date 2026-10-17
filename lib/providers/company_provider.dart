import 'package:flutter/material.dart';
import '../utils/combined_company_selection.dart';
import '../services/user_preferences_service.dart';

enum AppCompanyMode { single, combined }

class CompanyState extends ChangeNotifier {
  String? _selectedCompany;
  List<String> _selectedCompanies = const [];
  AppCompanyMode _mode = AppCompanyMode.single;
  Map<String, bool> _enabledFeatures = {};

  int _syncTrigger = 0;
  int _companyRevision = 0;
  bool _featuresLoaded = false;
  bool get featuresLoaded => _featuresLoaded;

  /// User-scoped (from users.is_combined_reports_enabled), not company_features.
  bool _userCombinedReportsEnabled = false;
  bool get userCombinedReportsEnabled => _userCombinedReportsEnabled;

  String? get selectedCompany => _selectedCompany;
  List<String> get selectedCompanies => List.unmodifiable(_selectedCompanies);
  AppCompanyMode get mode => _mode;
  bool get isCombinedMode => _mode == AppCompanyMode.combined;
  Map<String, bool> get enabledFeatures => _enabledFeatures;
  int get syncTrigger => _syncTrigger;
  /// Increments whenever the selected company / combined set changes or is cleared.
  int get companyRevision => _companyRevision;

  /// Stable isolation key for loads and IndexedStack remounts.
  String get scopeKey {
    if (_mode == AppCompanyMode.combined &&
        CombinedCompanySelection.isReady(_selectedCompanies)) {
      return 'combined:${CombinedCompanySelection.selectionKey(_selectedCompanies)}';
    }
    if (_selectedCompany != null && _selectedCompany!.trim().isNotEmpty) {
      return 'single:${_selectedCompany!.trim()}';
    }
    return 'none';
  }

  void setUserCombinedReportsEnabled(bool enabled) {
    if (_userCombinedReportsEnabled == enabled) return;
    _userCombinedReportsEnabled = enabled;
    if (!enabled && _mode == AppCompanyMode.combined) {
      _exitCombinedInternal();
    }
    notifyListeners();
  }

  bool isFeatureEnabled(String feature) {
    if (!_featuresLoaded) return false;
    // Opt-in features default OFF when the key is absent from older configs.
    const optInDefaultsOff = {
      'ls_perf_tally_formula',
    };
    bool enabled(String key) {
      if (_enabledFeatures.containsKey(key)) return _enabledFeatures[key]!;
      return !optInDefaultsOff.contains(key);
    }
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
      'db_qa_tally_cash_flow': ['tally_cash_flow'],
    };
    return (dependencies[feature] ?? const <String>[]).every(enabled);
  }

  void selectCompany(String company) {
    final trimmed = company.trim();
    if (trimmed.isEmpty) return;
    final modeChanged = _mode != AppCompanyMode.single;
    final companyChanged = _selectedCompany != trimmed;
    final hadCombined = _selectedCompanies.isNotEmpty;
    if (modeChanged || companyChanged || hadCombined) {
      _enabledFeatures = {};
      _featuresLoaded = false;
      _companyRevision++;
    }
    _mode = AppCompanyMode.single;
    _selectedCompany = trimmed;
    _selectedCompanies = const [];
    notifyListeners();
    // Persist asynchronously; do not block UI.
    UserPreferencesService.saveLastCompany(trimmed);
    UserPreferencesService.clearLastCombinedCompanies();
  }

  /// Enter Combined mode with a validated set (≥2 companies).
  /// Returns false if the set is not ready.
  bool enterCombinedMode(List<String> companies) {
    final normalized = CombinedCompanySelection.normalizeList(companies);
    if (!CombinedCompanySelection.isReady(normalized)) return false;

    final sameSet = _mode == AppCompanyMode.combined &&
        CombinedCompanySelection.selectionKey(_selectedCompanies) ==
            CombinedCompanySelection.selectionKey(normalized);
    if (!sameSet) {
      _enabledFeatures = {};
      _featuresLoaded = false;
      _companyRevision++;
    }
    _mode = AppCompanyMode.combined;
    _selectedCompany = null;
    _selectedCompanies = normalized;
    notifyListeners();
    UserPreferencesService.saveLastCombinedCompanies(normalized);
    UserPreferencesService.clearLastCompany();
    return true;
  }

  void setFeatures(Map<String, bool> features) {
    _enabledFeatures = Map<String, bool>.from(features);
    _featuresLoaded = true;
    notifyListeners();
  }

  /// Merge feature maps with OR (union) for Combined mode tab visibility.
  void setFeaturesUnion(Iterable<Map<String, bool>> featureMaps) {
    final merged = <String, bool>{};
    for (final map in featureMaps) {
      map.forEach((key, value) {
        merged[key] = (merged[key] ?? false) || value;
      });
    }
    setFeatures(merged);
  }

  void notifySyncCompleted() {
    _syncTrigger++;
    notifyListeners();
  }

  void clearCompany() {
    _featuresLoaded = false;
    _selectedCompany = null;
    _selectedCompanies = const [];
    _mode = AppCompanyMode.single;
    _enabledFeatures = {};
    _syncTrigger = 0;
    _companyRevision++;
    notifyListeners();
  }

  /// Call on logout so the next account does not inherit this flag.
  void clearUserCapabilities() {
    final wasCombined = _mode == AppCompanyMode.combined;
    _userCombinedReportsEnabled = false;
    if (wasCombined) {
      _exitCombinedInternal();
    }
    notifyListeners();
  }

  void _exitCombinedInternal() {
    _mode = AppCompanyMode.single;
    _selectedCompany = null;
    _selectedCompanies = const [];
    _enabledFeatures = {};
    _featuresLoaded = false;
    _companyRevision++;
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
