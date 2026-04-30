import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_web/firebase_storage_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'navigator_keys.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/app_bootstrap.dart';
import 'screens/home_screen.dart';
import 'utils/pinned_dashboard_registry.dart';
import 'web_startup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    configureWebStartup();
  }
  await initializeDateFormatting('en');
  String? initError;
  try {
    if (kIsWeb) {
      // Use DefaultFirebaseOptions (FlutterFire pattern). Do not call firebase.initializeApp() in
      // index.html — that can prevent Pigeon from wiring FirebaseCoreHostApi and causes channel-error.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // Bind Storage to the JS SDK. If this is skipped, [FirebaseStorage.instance] may keep using
      // Pigeon/MethodChannel (no web host) → uploads throw in messages.pigeon.dart.
      FirebaseStorageWeb.registerWith(Registrar());
    }
    if (SupabaseConfig.isConfigured) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    }
  } catch (e, st) {
    initError = e.toString();
    debugPrint('Init error: $e\n$st');
  }
  registerPinnedHomeDashboardPages(
    overview: () => const CustomizedDashboardPage(),
    project: () => const ProjectDashboardPage(),
  );
  runApp(MyApp(initError: initError));
}

/// Noto Sans TC covers Latin + Traditional Chinese so Flutter Web does not warn
/// about missing Noto fallbacks for CJK text.
ThemeData _appTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: GoogleFonts.notoSansTcTextTheme(base.textTheme),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initError});

  final String? initError;

  @override
  Widget build(BuildContext context) {
    if (initError != null) {
      return MaterialApp(
        title: 'Project Tracker',
        debugShowCheckedModeBanner: false,
        theme: _appTheme(),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'App failed to start',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(initError!, style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'Project Tracker',
        debugShowCheckedModeBanner: false,
        theme: _appTheme(),
        home: kIsWeb ? const AuthGate() : const AppBootstrap(),
      ),
    );
  }
}
