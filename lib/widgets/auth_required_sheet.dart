import 'package:flutter/material.dart';

import '../views/auth_common.dart';
import '../views/auth_entry_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

Future<void> showAuthRequiredSheet(BuildContext context) async {
  final bool? shouldLogin = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Devam etmek için giriş yapman gerekiyor.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(LucideIcons.logIn),
                label: const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted || shouldLogin != true) return;

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const AuthEntryScreen(mode: AuthFlowMode.login),
    ),
  );
}
