import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/koala_tokens.dart';

/// Uygulamanın herhangi bir yerinden SnackBar toast göstermek için global
/// servis. MaterialApp.scaffoldMessengerKey olarak [messengerKey] verildiğinde,
/// geçerli aktif route ne olursa olsun toast gösterilebilir.
///
/// Kullanım:
///   NotificationToastService.showIncomingMessage(
///     conversationId: 'abc',
///     designerName: 'Buse',
///     avatarUrl: '...',
///     preview: 'selam test',
///   );
class NotificationToastService {
  NotificationToastService._();

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Router global key (main.dart'ta MaterialApp.router'a verilir). Toast'a
  /// tıklayınca navigate etmek için kullanılır.
  static BuildContext? get _activeContext =>
      messengerKey.currentContext;

  /// Şu an aktif toast'un konuşma id'si — aynı sohbete ikinci mesaj geldiğinde
  /// önceki kapatılır.
  static String? _activeConvId;

  /// WhatsApp-tarzı in-app bildirim. Her ekranda çalışır.
  static void showIncomingMessage({
    required String conversationId,
    required String designerName,
    String? avatarUrl,
    required String preview,
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    // Aynı conv için önceki'yi kapat, yenisini göster.
    messenger.hideCurrentSnackBar();
    _activeConvId = conversationId;

    final initials = designerName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KoalaColors.surface,
        elevation: 8,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoalaRadius.lg),
          side: BorderSide(
            color: KoalaColors.accent.withValues(alpha: 0.25),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        content: InkWell(
          onTap: () {
            messenger.hideCurrentSnackBar();
            _openConversation(conversationId);
          },
          borderRadius: BorderRadius.circular(KoalaRadius.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [KoalaColors.accent, KoalaColors.accentMuted],
                  ),
                ),
                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? ClipOval(
                        child: Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      designerName,
                      style: KoalaText.label.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      style: KoalaText.bodySec.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chat_bubble_rounded,
                size: 18,
                color: KoalaColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _openConversation(String convId) {
    final ctx = _activeContext;
    if (ctx == null) return;
    try {
      ctx.push('/chat/dm/$convId');
    } catch (_) {}
  }

  /// Aktif conv id'sini döner — çağıran ekran (detail) zaten açıkken aynı
  /// conv için toast göstermek istemeyebilir.
  static String? get activeConvId => _activeConvId;
}
