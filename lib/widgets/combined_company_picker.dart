import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../utils/combined_company_selection.dart';

/// Multi-select company list + OK used for Combined app mode entry / Change.
class CombinedCompanyPickerBody extends StatelessWidget {
  final List<String> allowed;
  final Set<String> draftSelected;
  final Object? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback? onConfirm;
  final String? infoOverride;

  const CombinedCompanyPickerBody({
    super.key,
    required this.allowed,
    required this.draftSelected,
    required this.onRefresh,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    this.onConfirm,
    this.error,
    this.infoOverride,
  });

  List<String> get _draftValidated => CombinedCompanySelection.validateSelection(
        selected: draftSelected,
        allowed: allowed,
      );

  bool get _draftReady => CombinedCompanySelection.isReady(_draftValidated);

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load companies: $error'),
            const SizedBox(height: 12),
            TextButton(onPressed: onRefresh, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [
                Text(
                  infoOverride ??
                      'Select the companies to combine, then tap OK.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Companies',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: allowed.isEmpty ? null : onSelectAll,
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: draftSelected.isEmpty ? null : onClear,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (allowed.isEmpty)
                  _infoBox('No linked companies found for this user.')
                else if (allowed.length < CombinedCompanySelection.minCompanies)
                  _infoBox(
                    'You need at least 2 linked companies to use Combined mode.',
                  )
                else
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < allowed.length; i++) ...[
                            CheckboxListTile(
                              value: draftSelected.contains(allowed[i]),
                              onChanged: (_) => onToggle(allowed[i]),
                              title: Text(
                                allowed[i],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            if (i < allowed.length - 1)
                              Divider(height: 1, color: Colors.grey.shade200),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  _draftReady
                      ? '${_draftValidated.length} companies selected'
                      : 'Select at least ${CombinedCompanySelection.minCompanies} companies',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _draftReady
                        ? AppTheme.primaryColor
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _draftReady ? onConfirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoBox(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(text, style: const TextStyle(color: AppTheme.textSecondary)),
    );
  }
}
