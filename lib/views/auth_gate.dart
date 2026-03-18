import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main_shell.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<Widget> _routeFuture;

  @override
  void initState() {
    super.initState();
    _routeFuture = _decideRoute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Onboarding'de kullanılan resmi şimdiden yükle
    // AuthGate spinner dönerken decode tamamlanır
    precacheImage(
      const AssetImage('assets/images/koala_hero.png'),
      context,
    );
  }

  Future<Widget> _decideRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final user = FirebaseAuth.instance.currentUser;

    if (!onboardingDone) {
      return const OnboardingScreen();
    }

    if (user == null) {
      return const LoginScreen();
    }

    return const MainShell();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _routeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAFBFD),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
          );
        }
        return snapshot.data ?? const OnboardingScreen();
      },
    );
  }
}
