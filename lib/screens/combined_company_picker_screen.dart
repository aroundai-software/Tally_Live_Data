import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/combined_company_selection.dart';
import '../widgets/combined_company_picker.dart';
import 'main_shell.dart';

/// Full-screen Combined company picker (entry from company selection or Change).
class CombinedCompanyPickerScreen extends StatefulWidget {
  /// When true, OK replaces with MainShell; when false, pops with result list.
  final bool enterAppOnConfirm;
  final List<String>? initialSelected;

  const CombinedCompanyPickerScreen({
    super.key,
    this.enterAppOnConfirm = true,
    this.initialSelected,
  });

  @override
  State<CombinedCompanyPickerScreen> createState() =>
      _CombinedCompanyPickerScreenState();
}

class _CombinedCompanyPickerScreenState
    extends State<CombinedCompanyPickerScreen> {
  final SupabaseService _service = SupabaseService();
  bool _loading = true;
  Object? _error;
  List<String> _allowed = [];
  final Set<String> _draftSelected = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final linked = userId == null
          ? <String>[]
          : await _service.getUserCompanies(userId);
      final allowed = CombinedCompanySelection.normalizeList(linked);
      final seed = widget.initialSelected ??
          await UserPreferencesService.loadLastCombinedCompanies();
      final restored = CombinedCompanySelection.validateSelection(
        selected: seed,
        allowed: allowed,
      );
      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _draftSelected
          ..clear()
          ..addAll(restored);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<String> get _draftValidated => CombinedCompanySelection.validateSelection(
        selected: _draftSelected,
        allowed: _allowed,
      );

  void _toggle(String company) {
    setState(() {
      if (_draftSelected.contains(company)) {
        _draftSelected.remove(company);
      } else {
        _draftSelected.add(company);
      }
    });
  }

  Future<void> _confirm() async {
    final companies = _draftValidated;
    if (!CombinedCompanySelection.isReady(companies)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least 2 companies, then tap OK'),
        ),
      );
      return;
    }
    if (companies.length > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Loading ${companies.length} companies may be slower. Prefer fewer when possible.',
          ),
        ),
      );
    }
    final ok = CompanyProvider.of(context).enterCombinedMode(companies);
    if (!ok || !mounted) return;
    if (widget.enterAppOnConfirm) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MainShell()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pop(companies);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = CompanyProvider.of(context).userCombinedReportsEnabled;
    if (!enabled) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(
            'Combined',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              fontSize: 16,
            ),
          ),
          elevation: 0,
          backgroundColor: AppTheme.cardColor,
          iconTheme: IconThemeData(color: AppTheme.textPrimary),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Combined mode is disabled for your account. Ask an admin to enable it for you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(
        title: Text(
          widget.enterAppOnConfirm ? 'Select Companies' : 'Change Companies',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            fontSize: 16,
          ),
        ),
        elevation: 0,
        backgroundColor: AppTheme.cardColor,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CombinedCompanyPickerBody(
              allowed: _allowed,
              draftSelected: _draftSelected,
              error: _error,
              onRefresh: _bootstrap,
              onToggle: _toggle,
              onSelectAll: () => setState(() {
                _draftSelected
                  ..clear()
                  ..addAll(_allowed);
              }),
              onClear: () => setState(_draftSelected.clear),
              onConfirm: _confirm,
            ),
    );
  }
}
