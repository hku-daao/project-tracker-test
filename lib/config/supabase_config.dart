import 'environment_config.dart';

/// Supabase configuration (switches with [AppEnvironment]).
///
/// **Testing** — project *DAAO Tests* (`kxrimbbeyirmcjtszsvm`)  
/// **Production** — project *DAAO Apps* (`cjeyowmqhluiilrhkvmj`)
///
/// Paste the **anon public** key for *DAAO Tests* into [_testingAnonKey] below, or pass
/// `--dart-define=SUPABASE_ANON_KEY=...` at build time (overrides both environments).
///
/// See **docs/ENVIRONMENTS.md** in the repo root.
class SupabaseConfig {
  SupabaseConfig._();

  static const String _testingUrl =
      'https://kxrimbbeyirmcjtszsvm.supabase.co';
  static const String _productionUrl =
      'https://cjeyowmqhluiilrhkvmj.supabase.co';

  /// DAAO Apps — anon public (Project Settings → API).
  static const String _productionAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNqZXlvd21xaGx1aWlscmhrdm1qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3Mjc5MzksImV4cCI6MjA4OTMwMzkzOX0.-IW9pFlhuxHDImh7GZKRgPqCdbd-NE0gJTxsvEBvvOQ';

  /// DAAO Tests — anon public (Project Settings → API).
  static const String _testingAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt4cmltYmJleWlybWNqdHN6c3ZtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNDM4ODMsImV4cCI6MjA4OTgxOTg4M30.P_sWudLZq95NjTo_mPoSGnUrrZu9rciufzFZc09cB5w';

  /// e.g. `https://xxxxxxxx.supabase.co`
  static String get url =>
      AppEnvironment.isProduction ? _productionUrl : _testingUrl;

  static String get anonKey {
    const fromEnv =
        String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;
    return AppEnvironment.isProduction ? _productionAnonKey : _testingAnonKey;
  }

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
