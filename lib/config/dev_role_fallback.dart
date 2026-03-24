/// When /api/me returns no role (backend mismatch), map known test emails to roles for UI.
/// Prefer fixing app_users.firebase_uid + backend; this is a safety net.
class DevRoleFallback {
  DevRoleFallback._();

  static String? roleForEmail(String? email) {
    if (email == null || email.isEmpty) return null;
    final emailLower = email.toLowerCase();
    switch (emailLower) {
      case 'test-admin@test.com':
        return 'sys_admin';
      case 'test-dept@test.com':
        return 'dept_head';
      case 'test-super@test.com':
        return 'supervisor';
      case 'test-gen@test.com':
        return 'general';
      // Real users from database
      case 'yang.wang@hku.hk':
        return 'dept_head';
      case 'kenkylee@hku.hk':
        return 'supervisor';
      case 'lunanchow@hku.hk':
        return 'supervisor';
      case 'leec2@hku.hk':
        return 'general';
      default:
        return null;
    }
  }
}
