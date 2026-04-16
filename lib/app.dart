import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/global_message_listener.dart';
import 'services/notification_toast_service.dart';
import 'services/push_handler_service.dart';

class KoalaApp extends StatefulWidget {
  const KoalaApp({super.key});

  @override
  State<KoalaApp> createState() => _KoalaAppState();
}

class _KoalaAppState extends State<KoalaApp> {
  @override
  void initState() {
    super.initState();
    // Push notification deep link handler with foreground SnackBar
    PushHandlerService.initialize(
      appRouter,
      messengerKey: NotificationToastService.messengerKey,
    );
    // Global incoming-message listener — app ilk açıldığında başlar, uygulama
    // kapanana kadar yaşar. Her 1.5s Evlumba'yı pull eder ve yeni mesaj varsa
    // NotificationToastService ile herhangi bir ekranda toast gösterir.
    GlobalMessageListener.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Koala',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      scaffoldMessengerKey: NotificationToastService.messengerKey,
    );
  }
}
