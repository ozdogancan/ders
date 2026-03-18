import 'package:flutter/material.dart';

import 'auth_common.dart';
import 'auth_entry_screen.dart';

class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthEntryScreen(mode: AuthFlowMode.signup);
  }
}
