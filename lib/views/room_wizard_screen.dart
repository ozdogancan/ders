import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';
import 'package:lucide_icons/lucide_icons.dart';

class RoomWizardScreen extends StatelessWidget {
  const RoomWizardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Odanı Tasarla'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.slidersHorizontal,
                size: 64,
                color: KoalaColors.accentDeep,
              ),
              const SizedBox(height: 16),
              Text(
                'Oda Tasarım Sihirbazı',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Yakında burada olacak!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
