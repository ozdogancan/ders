import 'package:flutter/material.dart';

class KoalaLogo extends StatelessWidget {
  const KoalaLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/koala_logo.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(Icons.school, size: size, color: Colors.grey), // lucide-miss
    );
  }
}

class KoalaHero extends StatelessWidget {
  const KoalaHero({super.key, this.size = 120});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/koala_logo.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(Icons.school, size: size, color: Colors.grey), // lucide-miss
    );
  }
}
