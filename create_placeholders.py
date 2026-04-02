# Scan screen placeholder
s1 = """import 'package:flutter/material.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6C5CE7).withOpacity(0.08),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 36, color: Color(0xFF6C5CE7)),
            ),
            const SizedBox(height: 16),
            const Text('Tarama ekrani yaklnda', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ],
        ),
      ),
    );
  }
}
"""

with open('lib/views/scan_screen.dart', 'w', encoding='utf-8') as f:
    f.write(s1)
print('Done - scan_screen.dart')

# Explore screen placeholder
s2 = """import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/evlumba_service.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00B894).withOpacity(0.08),
                ),
                child: const Icon(Icons.explore_rounded, size: 36, color: Color(0xFF00B894)),
              ),
              const SizedBox(height: 16),
              const Text('Kesfet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Text('Ilham al, stilleri kesfet', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 50,
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(EvlumbaService.getExploreUrl('')), mode: LaunchMode.externalApplication),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text("evlumba'da Kesfet", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
"""

with open('lib/views/explore_screen.dart', 'w', encoding='utf-8') as f:
    f.write(s2)
print('Done - explore_screen.dart')
