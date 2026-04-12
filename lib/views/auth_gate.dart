import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/env.dart';
import '../core/theme/koala_tokens.dart';
import '../widgets/koala_widgets.dart';
import 'auth_common.dart';
import 'auth_entry_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

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
    precacheImage(const AssetImage('assets/images/koala_hero.png'), context);
  }

  Future<Widget> _decideRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_done') ?? false;
    final user = FirebaseAuth.instance.currentUser;

    if (!onboardingDone) {
      return const OnboardingScreen();
    }

    if (user == null && Env.requireLogin) {
      return const AuthEntryScreen(mode: AuthFlowMode.signup);
    }

    // REQUIRE_LOGIN=false ise kullanıcı null olsa bile uygulamaya devam et
    return const MainShell();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _routeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: KoalaColors.bgCool,
            body: LoadingState(),
          );
        }
        return snapshot.data ?? const OnboardingScreen();
      },
    );
  }
}
