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
      builder: (context, child) {
        // On desktop/tablet, constrain width and center
        final width = MediaQuery.of(context).size.width;
        if (width <= 600 || child == null) return child ?? const SizedBox();

        return Container(
          color: const Color(0xFFF1F5F9),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.symmetric(
                  vertical: BorderSide(
                    color: const Color(0xFFE2E8F0).withAlpha(80),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: ClipRect(child: child),
            ),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}
