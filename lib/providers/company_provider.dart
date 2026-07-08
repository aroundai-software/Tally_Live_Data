import 'package:flutter/material.dart';

class CompanyState extends ChangeNotifier {
  String? _selectedCompany;

  String? get selectedCompany => _selectedCompany;

  void selectCompany(String company) {
    _selectedCompany = company;
    notifyListeners();
  }

  void clearCompany() {
    _selectedCompany = null;
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
