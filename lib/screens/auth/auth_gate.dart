import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../app_bootstrap.dart';
import 'login_screen.dart';

/// Shows [LoginScreen] when no Firebase user; otherwise [AppBootstrap].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading…'),
                ],
              ),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        return const AppBootstrap();
      },
    );
  }
}
