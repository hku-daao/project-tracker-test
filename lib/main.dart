import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'config/supabase_config.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/app_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? initError;
  try {
    if (kIsWeb) {
      // Use DefaultFirebaseOptions (FlutterFire pattern). Do not call firebase.initializeApp() in
      // index.html — that can prevent Pigeon from wiring FirebaseCoreHostApi and causes channel-error.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
  runApp(MyApp(initError: initError));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initError});

  final String? initError;

  @override
  Widget build(BuildContext context) {
    if (initError != null) {
      return MaterialApp(
        title: 'Project/ Task Tracker',
        debugShowCheckedModeBanner: false,
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
        title: 'Project/ Task Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: kIsWeb ? const AuthGate() : const AppBootstrap(),
      ),
    );
  }
}
