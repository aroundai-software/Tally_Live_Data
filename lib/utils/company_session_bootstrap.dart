import '../providers/company_provider.dart';
import '../services/supabase_service.dart';
import '../services/user_preferences_service.dart';
import 'combined_company_selection.dart';

/// Applies profile flag + restores Combined or single company into [state].
/// Returns true when a scope was entered (caller can go to MainShell).
Future<bool> bootstrapCompanySession({
  required CompanyState state,
  required Map<String, dynamic> profile,
  required String userId,
  SupabaseService? service,
}) async {
  final svc = service ?? SupabaseService();
  state.setUserCombinedReportsEnabled(
    profile['is_combined_reports_enabled'] == true,
  );

  final linked = await svc.getUserCompanies(userId);

  if (state.userCombinedReportsEnabled &&
      linked.length >= CombinedCompanySelection.minCompanies) {
    final saved = await UserPreferencesService.loadLastCombinedCompanies();
    final restored = CombinedCompanySelection.validateSelection(
      selected: saved,
      allowed: linked,
    );
    if (CombinedCompanySelection.isReady(restored)) {
      return state.enterCombinedMode(restored);
    }
    if (saved.isNotEmpty) {
      await UserPreferencesService.clearLastCombinedCompanies();
    }
  }

  final lastCompany = await UserPreferencesService.loadLastCompany();
  if (lastCompany != null && linked.contains(lastCompany)) {
    state.selectCompany(lastCompany);
    return true;
  }

  final primary = profile['company_name']?.toString().trim() ?? '';
  if (primary.isNotEmpty &&
      (linked.contains(primary) || linked.isEmpty)) {
    // linked.isEmpty: legacy profile-only users still have a primary name.
    state.selectCompany(primary);
    return true;
  }

  if (linked.length == 1) {
    state.selectCompany(linked.first);
    return true;
  }

  return false;
}
