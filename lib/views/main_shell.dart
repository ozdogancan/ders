import 'package:flutter/material.dart';

import 'home_screen.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    // Single screen — no bottom nav needed anymore
    // Ustalaş removed for now, only Sorularım
    return const HomeScreen();
  }
}
