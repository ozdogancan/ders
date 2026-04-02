import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/push_handler_service.dart';

class KoalaApp extends StatefulWidget {
  const KoalaApp({super.key});

  @override
  State<KoalaApp> createState() => _KoalaAppState();
}

class _KoalaAppState extends State<KoalaApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Push notification deep link handler with foreground SnackBar
    PushHandlerService.initialize(appRouter, messengerKey: _messengerKey);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Koala',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      scaffoldMessengerKey: _messengerKey,
    );
  }
}
