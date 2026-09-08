import 'package:flutter/material.dart';

class CompanyState extends ChangeNotifier {
  String? _selectedCompany;
  Map<String, bool> _enabledFeatures = {};

  int _syncTrigger = 0;

  String? get selectedCompany => _selectedCompany;
  Map<String, bool> get enabledFeatures => _enabledFeatures;
  int get syncTrigger => _syncTrigger;

  bool isFeatureEnabled(String feature) {
    return _enabledFeatures[feature] ?? true;
  }

  void selectCompany(String company) {
    _selectedCompany = company;
    notifyListeners();
  }

  void setFeatures(Map<String, bool> features) {
    _enabledFeatures = features;
    notifyListeners();
  }

  void notifySyncCompleted() {
    _syncTrigger++;
    notifyListeners();
  }

  void clearCompany() {
    _selectedCompany = null;
    _enabledFeatures = {};
    _syncTrigger = 0;
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
