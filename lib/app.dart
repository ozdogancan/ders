import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'views/auth_gate.dart';

class AiTutorApp extends StatelessWidget {
  const AiTutorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koala',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}
