import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'evlumba_live_service.dart';
import 'messaging_service.dart';
import 'notification_toast_service.dart';

/// Uygulama boyunca yaşayan global mesaj dinleyicisi.
///
/// [KoalaApp.initState]'te `start()` ile başlar ve uygulama kapanana kadar
/// çalışır. Yapısı:
///   1) Her 1.5 sn'de bir `MessagingService.pullInbound()` çağırır (Evlumba →
///      Koala köprüsü). Dönüşte `lastInboundDetails` üzerinden yeni mesaj alan
///      conversation'ları tespit eder.
///   2) Yeni mesaj varsa Evlumba'dan son mesaj metnini + designer profilini
///      çeker ve `NotificationToastService.showIncomingMessage` ile toast
///      gösterir.
///   3) Ayrıca Evlumba realtime messages:INSERT event'ine abone olur — 1.5 sn
///      polling beklemeden anında pullInbound tetiklenir.
///
/// Böylece kullanıcı home, style_discovery, saved veya her hangi başka ekranda
/// olsa bile yeni mesaj geldiğinde toast görür.
class GlobalMessageListener {
  GlobalMessageListener._();

  // ignore: unused_field
  static Timer? _pollTimer;
  // ignore: unused_field
  static RealtimeChannel? _evlChannel;
  static bool _started = false;

  /// Bir conv için son toast gösterilen mesajın designer+count imzası —
  /// aynı mesaj için tekrar tekrar toast patlamasın.
  static final Map<String, String> _lastShownSig = {};

  /// Toast'u suppress et — kullanıcı aktif olarak o conversation'ın detail
  /// ekranındaysa toast göstermek yersiz.
  static String? suppressConvId;

  static void start() {
    if (_started) return;
    _started = true;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _tick();
    });
    _subscribeEvlumbaRealtime();
    // İlk açılışta hızlı tick
    _tick();
  }

  static Future<void> _tick() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final synced = await MessagingService.pullInbound();
      if (synced <= 0) return;
      final details = List<Map<String, dynamic>>.from(
        MessagingService.lastInboundDetails,
      );
      for (final d in details) {
        final count = (d['newMessages'] as int?) ?? 0;
        if (count <= 0) continue;
        final convId = (d['koalaConversationId'] ?? '').toString();
        final designerId = (d['designerId'] ?? '').toString();
        if (convId.isEmpty) continue;
        if (suppressConvId == convId) continue;

        // Bu conv için aynı imzayı zaten gösterdiysek tekrar gösterme.
        final sig = '$designerId|$count|${d['latestAt'] ?? ''}';
        if (_lastShownSig[convId] == sig) continue;
        _lastShownSig[convId] = sig;

        await _showToastForConv(
          convId: convId,
          designerId: designerId,
        );
      }
    } catch (e) {
      debugPrint('GlobalMessageListener._tick error: $e');
    }
  }

  static Future<void> _showToastForConv({
    required String convId,
    required String designerId,
  }) async {
    try {
      // Koala DB'den son mesajı al
      final lastMsg = await Supabase.instance.client
          .from('koala_direct_messages')
          .select('content, sender_id, created_at')
          .eq('conversation_id', convId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final content =
          (lastMsg?['content'] as String?)?.trim() ?? 'Yeni mesaj';
      final sender = lastMsg?['sender_id']?.toString() ?? '';
      // Kendi attığımız mesajsa toast gösterme
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null && sender == myUid) return;

      // Designer profilini al
      String designerName = 'Tasarımcı';
      String? avatarUrl;
      try {
        if (EvlumbaLiveService.isReady && designerId.isNotEmpty) {
          final list =
              await EvlumbaLiveService.getDesignersByIds([designerId]);
          if (list.isNotEmpty) {
            final p = list.first;
            final n = (p['full_name'] ?? p['business_name'] ?? '')
                .toString()
                .trim();
            if (n.isNotEmpty) designerName = n;
            final a = (p['avatar_url'] ?? '').toString().trim();
            if (a.isNotEmpty) avatarUrl = a;
          }
        }
      } catch (_) {}

      NotificationToastService.showIncomingMessage(
        conversationId: convId,
        designerName: designerName,
        avatarUrl: avatarUrl,
        preview: content,
      );
    } catch (e) {
      debugPrint('GlobalMessageListener._showToastForConv error: $e');
    }
  }

  /// Evlumba DB'sine direkt realtime abone ol — messages INSERT geldiği an
  /// pullInbound tetikle (1.5 sn poll'u beklemeden).
  static Future<void> _subscribeEvlumbaRealtime() async {
    try {
      if (!EvlumbaLiveService.isReady) {
        final ok = await EvlumbaLiveService.waitForReady(
          timeout: const Duration(seconds: 10),
        );
        if (!ok) return;
      }
      if (_evlChannel != null) return;
      final client = EvlumbaLiveService.client;
      final ch = client.channel('koala_global_inbound');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => _tick(),
      ).subscribe();
      _evlChannel = ch;
      debugPrint('GlobalMessageListener: subscribed to Evlumba messages');
    } catch (e) {
      debugPrint('GlobalMessageListener: evlumba subscribe failed: $e');
    }
  }
}
