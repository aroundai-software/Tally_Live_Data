import 'package:flutter/material.dart';
import 'combined_company_picker_screen.dart';

/// Legacy route: Combined is now an app mode. Redirects to the picker.
@Deprecated('Use CombinedCompanyPickerScreen / Combined app mode')
class CombinedReportsScreen extends StatelessWidget {
  const CombinedReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CombinedCompanyPickerScreen(enterAppOnConfirm: true);
  }
}
