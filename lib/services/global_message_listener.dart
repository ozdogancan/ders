import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
///
/// Merkezi polling: Tüm ekranlar bu singleton'un `syncTick` notifier'ını
/// dinler. Home / ChatList / v2 kendi ayrı `Timer.periodic`lerini tutmaz —
/// DO Frankfurt 1vCPU sunucuyu korumak için poll fırtınası kaldırıldı.
///
/// Adaptif interval:
///   - Foreground (resumed/inactive)  : 15 sn
///   - Background (hidden)            : 60 sn
///   - Paused / detached              : timer durur
/// Realtime INSERT event geldiğinde timer reset olur — event zaten mesajı
/// getirdiği için hemen arkasından boş poll yapılmaz (debounce/coalesce).
class GlobalMessageListener {
  GlobalMessageListener._();

  static Timer? _pollTimer;
  static RealtimeChannel? _evlChannel;
  static bool _started = false;
  static StreamSubscription<User?>? _authSub;
  static _LifecycleBridge? _lifecycleBridge;
  static AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  // Re-entrancy lock — yavaş ağda tick'ler üst üste binmesin.
  static bool _inFlight = false;

  static const Duration _fgInterval = Duration(seconds: 15);
  static const Duration _bgInterval = Duration(seconds: 60);

  /// Bir conv için son toast gösterilen mesajın designer+count imzası —
  /// aynı mesaj için tekrar tekrar toast patlamasın.
  static final Map<String, String> _lastShownSig = {};

  /// Toast'u suppress et — kullanıcı aktif olarak o conversation'ın detail
  /// ekranındaysa toast göstermek yersiz.
  static String? suppressConvId;

  /// Her başarılı inbound sync sonrası (yeni mesaj geldi mi geldi) tetiklenir.
  /// UI widget'ları buna abone olarak badge/ListView'larını tazeleyebilir.
  /// Realtime subscription'a güvenmek yerine explicit notify — sync → refresh.
  static final ValueNotifier<int> syncTick = ValueNotifier<int>(0);

  static void start() {
    if (_started) return;
    _started = true;

    _lifecycleBridge ??= _LifecycleBridge(_onLifecycleChanged);
    WidgetsBinding.instance.addObserver(_lifecycleBridge!);

    _restartTimer();
    _subscribeEvlumbaRealtime();
    // Sign-out olduğunda realtime channel'ı temizle — aksi halde Evlumba
    // tarafında koala_global_inbound kanalı sızdırılır (her cold-start yeni
    // channel bindirir). Fonksiyonel etki yok, sadece memory/connection
    // hijyeni.
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _disposeEvlumbaChannel();
      }
    });
    // İlk açılışta hızlı tick
    _tick();
  }

  /// Adaptif interval: foreground 15s, background 60s, paused/detached stop.
  static void _restartTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final interval = _intervalForLifecycle(_lifecycle);
    if (interval == null) return; // paused/detached → no timer
    _pollTimer = Timer.periodic(interval, (_) => _tick());
  }

  static Duration? _intervalForLifecycle(AppLifecycleState s) {
    switch (s) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        return _fgInterval;
      case AppLifecycleState.hidden:
        return _bgInterval;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        return null;
    }
  }

  static void _onLifecycleChanged(AppLifecycleState s) {
    _lifecycle = s;
    _restartTimer();
    // Foreground'a döndüyse anında tick — kullanıcı 60s beklemesin.
    if (s == AppLifecycleState.resumed) {
      _tick();
    }
  }

  static void _disposeEvlumbaChannel() {
    final ch = _evlChannel;
    if (ch == null) return;
    try {
      EvlumbaLiveService.client.removeChannel(ch);
    } catch (e) {
      debugPrint('GlobalMessageListener: removeChannel failed: $e');
    }
    _evlChannel = null;
  }

  static Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      // İlk tick'te backfill — eski NULL-status conv'ları 'active' yap.
      unawaited(MessagingService.backfillNullStatusConversations());
      final synced = await MessagingService.pullInbound();
      // Her tick sonrası notify — "yeni yok" bile olsa badge consistent olsun
      // (server başka sekmede read_at attıysa vs.)
      syncTick.value = syncTick.value + 1;
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
        // latestEvlId evlumba mesaj ID'si — her mesaj unique, iki farklı mesaj
        // gelse de count=1 tekrar aynı sig olmaz.
        final latestId = (d['latestEvlId'] ?? '').toString();
        final latestAt = (d['latestAt'] ?? '').toString();
        final sig = latestId.isNotEmpty
            ? latestId
            : '$designerId|$count|$latestAt|${DateTime.now().millisecondsSinceEpoch}';
        if (_lastShownSig[convId] == sig) continue;
        _lastShownSig[convId] = sig;

        await _showToastForConv(
          convId: convId,
          designerId: designerId,
        );
      }
    } catch (e) {
      debugPrint('GlobalMessageListener._tick error: $e');
    } finally {
      _inFlight = false;
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
        designerId: designerId,
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
        callback: (_) {
          // Event geldi → hemen tick. Sonra timer'ı reset et; bir sonraki
          // tick interval süresi sonra olsun — arka arkaya gereksiz poll'u
          // önler (coalesce).
          _tick();
          _restartTimer();
        },
      ).subscribe();
      _evlChannel = ch;
      debugPrint('GlobalMessageListener: subscribed to Evlumba messages');
    } catch (e) {
      debugPrint('GlobalMessageListener: evlumba subscribe failed: $e');
    }
  }
}

/// WidgetsBindingObserver alt-sınıflamak static context'te mümkün değil —
/// küçük bir bridge class.
class _LifecycleBridge with WidgetsBindingObserver {
  _LifecycleBridge(this._onChange);
  final void Function(AppLifecycleState) _onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onChange(state);
  }
}
