/// Server-backed admin gate. Only `users.role == super_admin` (and active).
/// Do not grant access from email/phone string matches.
bool isActiveSuperAdmin(Map<String, dynamic>? profile) {
  if (profile == null) return false;
  if (profile['is_active'] != true) return false;
  return profile['role']?.toString() == 'super_admin';
}

bool isSuperAdminRole(Object? role) => role?.toString() == 'super_admin';
