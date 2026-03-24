/// Compile-time deploy target for the Flutter app.
///
/// | `DEPLOY_ENV`   | Supabase    | Railway backend |
/// |----------------|-------------|-----------------|
/// | `testing` (default) | DAAO Tests | Calvin's Test Space |
/// | `production`   | DAAO Apps   | DAAO Apps |
///
/// Firebase uses the **same** project (`daao-a20c6`) for both; only hosting URL differs.
///
/// ### Build examples (web)
/// ```bash
/// # Testing stack (default)
/// flutter build web --release --no-wasm-dry-run
///
/// # Production stack
/// flutter build web --release --no-wasm-dry-run --dart-define=DEPLOY_ENV=production
/// ```
///
/// ### Optional overrides (either environment)
/// - `--dart-define=SUPABASE_ANON_KEY=...` — overrides the anon key from [SupabaseConfig].
/// - `--dart-define=API_BASE_URL=https://...` — overrides [ApiConfig.baseUrl].
class AppEnvironment {
  AppEnvironment._();

  /// `testing` (default) or `production`.
  static const String deployEnv =
      String.fromEnvironment('DEPLOY_ENV', defaultValue: 'testing');

  static bool get isProduction =>
      deployEnv.toLowerCase() == 'production';

  static bool get isTesting => !isProduction;

  /// Short label for UI / logs.
  static String get label => isProduction ? 'production' : 'testing';
}
