import 'package:flutter/material.dart';
import 'home_screen.dart';

/// MainShell — artık sadece HomeScreen'i sarıyor.
/// Bottom nav kaldırıldı, hub-style navigasyon HomeScreen içinde.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
