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
      // OEM font-scale sabitleme: Samsung/Xiaomi gibi cihazlarda sistem yazı
      // boyutu %130-140'a çekildiğinde home hero'su ("koala" 44px) + onboarding
      // kartları devasa görünüyor / taşıyor. Marka kimliği pikselle bağlı
      // olduğu için sistem ölçeğini tamamen yok sayıp 1.0'a sabitliyoruz.
      // Kullanıcı sistem genelinde büyük ekran ayarını (Display Size) hâlâ
      // değiştirebilir — o tüm UI'yı oransal büyütür, layout'u bozmaz.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.noScaling),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
