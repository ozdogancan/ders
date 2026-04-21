import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../core/config/env.dart';

/// Mesaj tipi
enum MessageType { text, image, file, system }

/// Kullanici <-> Tasarimci direct messaging servisi.
/// AI chat degil — gercek kisiler arasi mesajlasma.
/// Supabase Realtime ile canli dinleme destekli.
class MessagingService {
  MessagingService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static SupabaseClient get _db => Supabase.instance.client;

  /// Public getter — UI'da unread count hesabi icin
  static String? get currentUserId => _uid;

  /// sendMessage çağrısı null döndüğünde son hatayı bu değişkenden okuyabilir.
  /// UI sticky toast'ta gerçek RLS/exception metnini göstermek için kullanır.
  /// Her çağrı başında temizlenir.
  static String? lastSendError;

  /// Conversation (başlatma/bulma/detay) çağrıları null döndüğünde UI bu alandan
  /// gerçek hatayı okur; "Sohbet başlatılamadı" yerine spesifik mesaj gösterir.
  static String? lastConvError;

  /// Firebase auth henüz restore edilmemiş olabilir (özellikle hard refresh
  /// sonrası). currentUser null ise authStateChanges ile gelen ilk user'ı
  /// kısa bir timeout ile bekler; yoksa null döner.
  /// 8s default — yavaş cihaz/ağlarda IndexedDB restore uzayabilir, conversation
  /// listesi boş gözükmesindense küçük bir gecikme ile doğru liste daha iyidir.
  static Future<String?> _waitForUid({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final direct = FirebaseAuth.instance.currentUser?.uid;
    if (direct != null) return direct;
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(timeout);
      return user?.uid;
    } catch (_) {
      return FirebaseAuth.instance.currentUser?.uid;
    }
  }

  /// Tek noktada auth + Supabase + RLS-header hazırlığı.
  /// Bu metottan başarıyla dönüldüğünde:
  ///   1. Supabase config yüklenmiş
  ///   2. Firebase user var (gerekirse anonim sign-in burada tetiklenir)
  ///   3. `x-user-id` header'ı uid ile set edildi
  ///
  /// Fail durumunda açıklayıcı [StateError] fırlatır — caller yakalayıp
  /// [lastConvError]'a yazar, UI de gerçek mesajı snackbar'da gösterir.
  /// Bu, sessiz null dönüşlerin yerini alır.
  static Future<String> _ensureReady() async {
    if (!Env.hasSupabaseConfig) {
      throw StateError('Supabase yapılandırması yüklenemedi.');
    }
    // 1. Hazır uid varsa direkt
    var uid = FirebaseAuth.instance.currentUser?.uid;
    // 2. authStateChanges restore bekle (kısa: 3s)
    if (uid == null) {
      try {
        final user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 3));
        uid = user?.uid;
      } catch (_) {}
    }
    // 3. Hâlâ null → anonim sign-in'i KENDİMİZ tetikle.
    //    main.dart'taki signInAnonymously sessizce fail etmiş olabilir
    //    (network dip, guard flag, vs.). Burada retry garantisi.
    if (uid == null) {
      try {
        final cred = await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 8));
        uid = cred.user?.uid;
      } catch (e) {
        throw StateError('Oturum açılamadı (anon sign-in): $e');
      }
    }
    if (uid == null) {
      throw StateError('Firebase oturumu yok.');
    }
    // 4. RLS için x-user-id header'ı — her çağrı öncesi emniyete al.
    try {
      _db.rest.headers['x-user-id'] = uid;
    } catch (_) {}
    return uid;
  }

  // Aktif realtime subscription'lar
  static final Map<String, RealtimeChannel> _channels = {};

  /// One-time backfill: eski inbound route'un status set etmediği için NULL
  /// kalan koala_conversations row'larını 'active' yap. Idempotent.
  static bool _statusBackfillDone = false;
  static Future<void> backfillNullStatusConversations() async {
    if (_statusBackfillDone) return;
    if (!Env.hasSupabaseConfig) return;
    final uid = await _waitForUid();
    if (uid == null) return;
    try {
      await _db
          .from('koala_conversations')
          .update({'status': 'active'})
          .or('user_id.eq.$uid,designer_id.eq.$uid')
          .filter('status', 'is', null);
      _statusBackfillDone = true;
      debugPrint('MessagingService: null-status conversations backfilled');
    } catch (e) {
      debugPrint('MessagingService.backfillNullStatusConversations error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // CONVERSATIONS (sohbet odalari)
  // ═══════════════════════════════════════════════════════

  /// Sohbet baslat veya mevcut olani getir (upsert).
  /// [contextType]: hangi ekrandan gelindi (project, product, designer, ai_chat)
  /// [contextId]: ilgili kaynak ID'si
  /// [contextTitle]: ilgili kaynak basligi (inquiry mesajinda kullanilir)
  ///
  /// Öncelikle koala-api `/api/conversations/ensure` (service_role) çağırılır —
  /// bu, Supabase RLS + x-user-id header race'ini tamamen devre dışı bırakır.
  /// Anne/babanın Android cihazlarında sürekli "tekrar dene" hatası veren
  /// sessiz RLS reject'i bu yolla çözülüyor. API fail olursa eski Supabase
  /// direct path'i fallback olarak dener.
  static Future<Map<String, dynamic>?> getOrCreateConversation({
    required String designerId,
    String? contextType,
    String? contextId,
    String? contextTitle,
  }) async {
    lastConvError = null;
    final String uid;
    try {
      uid = await _ensureReady();
    } catch (e) {
      lastConvError = e.toString();
      debugPrint('getOrCreateConversation: auth not ready: $e');
      return null;
    }

    // 1) Server-side ensure (primary path) — RLS bypass + users row upsert.
    final apiUrl = Env.koalaApiUrl;
    if (apiUrl.isNotEmpty) {
      try {
        final fbUser = FirebaseAuth.instance.currentUser;
        final res = await http
            .post(
              Uri.parse('$apiUrl/api/conversations/ensure'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'firebaseUid': uid,
                'designerId': designerId,
                'title': contextTitle,
                if (fbUser?.email != null) 'email': fbUser!.email,
                if (fbUser?.displayName != null)
                  'displayName': fbUser!.displayName,
                if (fbUser?.photoURL != null) 'photoUrl': fbUser!.photoURL,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final body = jsonDecode(res.body);
          if (body is Map<String, dynamic>) return body;
        } else {
          debugPrint(
              'getOrCreateConversation: API ${res.statusCode} ${res.body}');
          try {
            final errBody = jsonDecode(res.body);
            if (errBody is Map && errBody['error'] is String) {
              lastConvError = 'API: ${errBody['error']}';
            } else {
              lastConvError = 'API ${res.statusCode}';
            }
          } catch (_) {
            lastConvError = 'API ${res.statusCode}';
          }
        }
      } catch (e) {
        debugPrint('getOrCreateConversation: API call failed: $e');
        lastConvError = 'API: $e';
      }
    }

    // 2) Fallback: Supabase direct (RLS'e tabi — API ulaşılamıyorsa son şans).
    try {
      final existing = await _db
          .from('koala_conversations')
          .select()
          .eq('user_id', uid)
          .eq('designer_id', designerId)
          .maybeSingle();

      if (existing != null) {
        lastConvError = null;
        return existing;
      }

      final res = await _db.from('koala_conversations').insert({
        'user_id': uid,
        'designer_id': designerId,
        'title': contextTitle,
      }).select().single();

      lastConvError = null;
      return res;
    } catch (e) {
      debugPrint('MessagingService.getOrCreateConversation fallback error: $e');
      // API hatası zaten lastConvError'a yazıldı; fallback'in hatası üzerine
      // yazılmasın ki UI hangi path'in fail ettiğini gösterebilsin. Yine de
      // lastConvError null ise (API başarılı ama body parse etmedi vs.) yaz.
      lastConvError ??= e.toString();
      return null;
    }
  }

  /// Var olan bir sohbeti SADECE bulmak için — yoksa null döner, insert YAPMAZ.
  /// Popup'larda lazy-create kullanılırken "önce var mı?" kontrolü burada.
  static Future<Map<String, dynamic>?> findExistingConversation({
    required String designerId,
  }) async {
    lastConvError = null;
    final String uid;
    try {
      uid = await _ensureReady();
    } catch (e) {
      lastConvError = e.toString();
      return null;
    }
    try {
      return await _db
          .from('koala_conversations')
          .select()
          .eq('user_id', uid)
          .eq('designer_id', designerId)
          .maybeSingle();
    } catch (e) {
      debugPrint('MessagingService.findExistingConversation error: $e');
      lastConvError = e.toString();
      return null;
    }
  }

  /// Eski API uyumluluk alias
  static Future<Map<String, dynamic>?> startConversation({
    required String designerId,
    String? title,
  }) => getOrCreateConversation(designerId: designerId, contextTitle: title);

  /// Kullanicinin tum sohbetlerini getir (son mesaja gore sirali)
  static Future<List<Map<String, dynamic>>> getConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    if (!Env.hasSupabaseConfig) return [];
    final uid = await _waitForUid();
    if (uid == null) return [];
    try {
      // SQL'de status filtresi YOK — null status'lu eski conv'lar da dahil
      // edilsin diye. 'archived' filter Dart tarafında yapılıyor.
      final res = await _db
          .from('koala_conversations')
          .select('id, user_id, designer_id, title, last_message, last_message_at, unread_count_user, unread_count_designer, status')
          .or('user_id.eq.$uid,designer_id.eq.$uid')
          .order('last_message_at', ascending: false)
          .range(offset, offset + limit - 1);
      final all = List<Map<String, dynamic>>.from(res);
      // 1. Archived + hiç mesaj olmayan (last_message_at null) sohbetleri at.
      final filtered = all
          .where((c) =>
              c['status'] != 'archived' && c['last_message_at'] != null)
          .toList();
      if (filtered.isEmpty) return filtered;

      // 2. "Kendim hiçbir şey yazmamışım" sohbetleri listeden çıkar —
      // designer mesaj atsa bile user input'tan bir şey göndermediyse
      // messages ekranında gözükmesin (kullanıcı isteği).
      // Tek sorguda: bu conv ID'leri içinden user'ın sender olduğu mesajları çek.
      final convIds = filtered.map((c) => c['id'].toString()).toList();
      try {
        final sent = await _db
            .from('koala_direct_messages')
            .select('conversation_id')
            .eq('sender_id', uid)
            .inFilter('conversation_id', convIds);
        final hasSent = <String>{
          for (final row in (sent as List))
            (row as Map)['conversation_id'].toString(),
        };
        return filtered
            .where((c) => hasSent.contains(c['id'].toString()))
            .toList();
      } catch (e) {
        // Filter çökerse liste tamamen boş görünmesin — fallback
        debugPrint('MessagingService: sender-filter failed, returning all: $e');
        return filtered;
      }
    } catch (e) {
      debugPrint('MessagingService.getConversations error: $e');
      rethrow;
    }
  }

  /// Tek conversation detay
  static Future<Map<String, dynamic>?> getConversation(String id) async {
    lastConvError = null;
    final String uid;
    try {
      uid = await _ensureReady();
    } catch (e) {
      lastConvError = e.toString();
      return null;
    }
    try {
      final res = await _db
          .from('koala_conversations')
          .select()
          .eq('id', id)
          .or('user_id.eq.$uid,designer_id.eq.$uid')
          .single();
      return res;
    } catch (e) {
      debugPrint('MessagingService.getConversation error: $e');
      lastConvError = e.toString();
      return null;
    }
  }

  /// Sohbeti arsivle
  static Future<bool> archiveConversation(String conversationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return false;
    try {
      await _db
          .from('koala_conversations')
          .update({'status': 'archived', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', conversationId)
          .or('user_id.eq.$_uid,designer_id.eq.$_uid');
      return true;
    } catch (e) {
      debugPrint('MessagingService.archiveConversation error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // MESSAGES (mesajlar)
  // ═══════════════════════════════════════════════════════

  /// Mesaj gonder
  static Future<Map<String, dynamic>?> sendMessage({
    required String conversationId,
    required String content,
    MessageType type = MessageType.text,
    String? attachmentUrl,
    Map<String, dynamic>? metadata,
  }) async {
    lastSendError = null;
    final String uid;
    try {
      uid = await _ensureReady();
    } catch (e) {
      lastSendError = e.toString();
      return null;
    }
    try {

      // 1. Mesaji ekle
      final msg = await _db.from('koala_direct_messages').insert({
        'conversation_id': conversationId,
        'sender_id': uid,
        'content': content,
        'message_type': type.name,
        if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        if (metadata != null) 'metadata': metadata,
      }).select().single();

      // 2. Conversation'i guncelle (son mesaj + unread count)
      final conv = await _db
          .from('koala_conversations')
          .select('user_id, designer_id')
          .eq('id', conversationId)
          .single();

      final isUser = conv['user_id'] == uid;
      final unreadField = isUser ? 'unread_count_designer' : 'unread_count_user';

      // RPC ile unread artır (yoksa sessizce geç)
      try {
        await _db.rpc('increment_unread', params: {
          'conv_id': conversationId,
          'field_name': unreadField,
        });
      } catch (_) {
        // RPC henuz kurulu degil — devam et
      }

      // last_message guncelle.
      // RLS policy: user_id = get_user_id() OR designer_id = get_user_id().
      // .eq('id', ...) tek basina yeterli gorunse de bazi edge case'lerde
      // RLS ile 0 satir etkileyip sessizce gecebiliyor — WHERE'e or() ekliyoruz
      // ki filtre policy ile birebir ayni olsun. Ayrica .select('id') ile
      // satirin guncellenip guncellenmedigini dogruluyoruz; 0 satir donerse
      // chat_list sort bozuluyor, debug log biraksin.
      try {
        // NOT: DateTime.now().toIso8601String() offset suffix'i YOK,
        // Supabase TIMESTAMPTZ'ye UTC olarak yaziyor -> istemci geri
        // okuyunca "gelecek zaman" cikip timeAgo "Simdi" donduruyor.
        // .toUtc() ile dogru UTC ISO (Z suffix'li) yaz.
        final nowIso = DateTime.now().toUtc().toIso8601String();
        // Image mesajlari icin last_message'a "[image]" marker ekle.
        // Chat list bu marker'i parse edip foto ikonu + caption gosterir.
        // Caption (content) bos olabilir → sadece "[image]".
        final lastMessageStr = type == MessageType.image
            ? (content.trim().isEmpty ? '[image]' : '[image] $content')
            : content;
        final upd = await _db
            .from('koala_conversations')
            .update({
              'last_message': lastMessageStr,
              'last_message_at': nowIso,
              'updated_at': nowIso,
            })
            .eq('id', conversationId)
            .or('user_id.eq.$uid,designer_id.eq.$uid')
            .select('id, last_message_at');
        if ((upd as List).isEmpty) {
          debugPrint(
              'sendMessage: koala_conversations UPDATE 0 rows (conv=$conversationId, uid=$uid) — RLS block?');
        }
      } catch (e) {
        debugPrint('sendMessage: conv UPDATE failed: $e');
      }

      // 3. Evlumba bridge — fire-and-forget; client UX'ini bekletmez.
      //    Kullanıcı → tasarımcı yönünde mesajları Evlumba DB'sine de yazar
      //    ki tasarımcı evlumba.com/mesajlar'dan görebilsin.
      //    Hem text hem image type'i bridge edilir; image'da attachmentUrl da
      //    iletilir, body caption (boş olabilir).
      if (isUser &&
          (type == MessageType.text || type == MessageType.image)) {
        unawaited(_bridgeToEvlumba(
          designerId: conv['designer_id'] as String,
          body: content,
          koalaConversationId: conversationId,
          attachmentUrl: type == MessageType.image ? attachmentUrl : null,
        ));
      }

      return msg;
    } catch (e) {
      debugPrint('MessagingService.sendMessage error: $e');
      lastSendError = e.toString();
      return null;
    }
  }

  /// Bir sohbetin mesajlarini getir (sayfalamali, en yeniden).
  /// [beforeId] verilirse o mesajdan onceki mesajlari getirir (cursor pagination).
  static Future<List<Map<String, dynamic>>> getMessages({
    required String conversationId,
    int limit = 30,
    int offset = 0,
    String? beforeId,
  }) async {
    if (_uid == null || !Env.hasSupabaseConfig) return [];
    try {
      var query = _db
          .from('koala_direct_messages')
          .select()
          .eq('conversation_id', conversationId);

      if (beforeId != null) {
        // Cursor-based: o ID'nin created_at'inden onceki mesajlar
        final pivot = await _db
            .from('koala_direct_messages')
            .select('created_at')
            .eq('id', beforeId)
            .maybeSingle();
        if (pivot == null) {
          // Pivot kaybolmuşsa (silinmiş mesaj vb.) tüm mesajları tekrar çekip
          // sonsuz pagination döngüsüne girmek yerine boş liste dön.
          return [];
        }
        query = query.lt('created_at', pivot['created_at']);
      }

      final res = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('MessagingService.getMessages error: $e');
      return [];
    }
  }

  /// markAsRead için ayrıntılı sonuç — hangi adımda fail ettiğini UI'a
  /// göstermek için. null hata = success.
  static String? lastMarkAsReadError;

  /// Mesajlari okundu olarak isaretle — auth restore race'ine karsi dayanikli.
  /// Silent failures yerine detaylı hata dönen [lastMarkAsReadError] set eder.
  static Future<bool> markAsRead(String conversationId) async {
    lastMarkAsReadError = null;
    if (!Env.hasSupabaseConfig) {
      lastMarkAsReadError = 'Supabase config yok';
      return false;
    }
    final uid = await _waitForUid();
    if (uid == null) {
      lastMarkAsReadError = 'Oturum uid yok';
      return false;
    }
    // Request bazlı x-user-id'yi garanti altına al — kimi senaryolarda
    // main.dart'taki listener set edemeden ilk UPDATE gidebiliyor.
    try {
      _db.rest.headers['x-user-id'] = uid;
    } catch (_) {}

    // NOTE: koala_direct_messages.read_at kolonu production DB'de yok
    // (migration 004 eksik). Read state conversation seviyesinde tutuluyor.
    // Step 1 (msg row update) bu yüzden kaldırıldı.

    // 2) Unread sayacını SELECT yapmadan doğrudan sıfırla.
    //    Önceden SELECT + branch yapıyorduk; ancak RLS race veya id aramasında
    //    tek satırın dönmemesi `conv == null` → sessiz false yol açıyordu.
    //    İki ayrı UPDATE: biri user perspektifinden, biri designer perspektifinden.
    //    Hangisi kullanıcıya aitse eşleşir; diğeri 0 satırı etkiler, zarar yok.
    //    UPDATE ardından .select() çağırıyoruz — PostgREST RLS reddettiğinde
    //    0 satır döner, yoksa "success ama hiçbir şey güncellenmedi" durumu
    //    bize true dönmez.
    final nowIso = DateTime.now().toIso8601String();
    int rowsAffected = 0;
    String? lastErr;
    try {
      final res = await _db.from('koala_conversations').update({
        'unread_count_user': 0,
        'updated_at': nowIso,
      }).eq('id', conversationId).eq('user_id', uid).select('id');
      rowsAffected += res.length;
    } catch (e) {
      debugPrint('markAsRead step2a (user zero) failed: $e');
      lastErr = 'UserUpd: $e';
    }
    try {
      final res = await _db.from('koala_conversations').update({
        'unread_count_designer': 0,
        'updated_at': nowIso,
      }).eq('id', conversationId).eq('designer_id', uid).select('id');
      rowsAffected += res.length;
    } catch (e) {
      debugPrint('markAsRead step2b (designer zero) failed: $e');
      lastErr = 'DesignerUpd: $e';
    }

    if (rowsAffected == 0) {
      lastMarkAsReadError ??= lastErr ?? 'Conversation UPDATE 0 satır (RLS? uid=$uid)';
      return false;
    }
    // Mesaj update fail etmiş olsa bile conv sayacı sıfırlanmış olabilir.
    // Kullanıcıya optimistic'i bozmayalım — true dönelim.
    return true;
  }

  // ═══════════════════════════════════════════════════════
  // EVLUMBA BRIDGE
  // ═══════════════════════════════════════════════════════

  /// Son pullInbound sonucunun diag bilgisi — UI "Sync" butonunda gösterilir.
  static Map<String, dynamic>? lastInboundDiag;
  static int lastInboundConversations = 0;

  /// Son pullInbound'da YENİ mesaj alan conversation detayları. Her entry:
  ///   { 'designerId': '...', 'koalaConversationId': '...', 'newMessages': N }
  /// Global toast listener bunu kullanır.
  static List<Map<String, dynamic>> lastInboundDetails = const [];

  /// Evlumba → Koala ters köprü (client-pull).
  /// Flutter app ChatListScreen açılınca / app foreground'a gelince çağırır.
  /// Designer'ın evlumba.com'dan attığı mesajları Koala DB'sine çeker.
  /// Dönüş: toplam yeni senkronize edilen mesaj sayısı (hata olursa 0).
  static Future<int> pullInbound() async {
    final uid = await _waitForUid();
    if (uid == null) return 0;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;
    final apiUrl = Env.koalaApiUrl;
    if (apiUrl.isEmpty) return 0;

    try {
      final res = await http
          .post(
            Uri.parse('$apiUrl/api/messages/inbound'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firebaseUid': user.uid,
              'email': user.email,
              'displayName': user.displayName,
              'avatarUrl': user.photoURL,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final n = (body['synced'] as int?) ?? 0;
          lastInboundConversations = (body['conversations'] as int?) ?? 0;
          lastInboundDiag = body['diag'] as Map<String, dynamic>?;
          final rawDetails = body['details'];
          if (rawDetails is List) {
            lastInboundDetails = rawDetails
                .whereType<Map<String, dynamic>>()
                .toList();
          } else {
            lastInboundDetails = const [];
          }
          if (n > 0) {
            debugPrint('MessagingService: pullInbound synced $n messages');
          }
          return n;
        } catch (_) {
          return 0;
        }
      }
      debugPrint('MessagingService: pullInbound failed ${res.statusCode} ${res.body}');
      return 0;
    } catch (e) {
      debugPrint('MessagingService: pullInbound error $e');
      return 0;
    }
  }

  /// Koala → Evlumba mesaj köprüsü (fire-and-forget).
  /// Koala kullanıcısının mesajını Evlumba DB'sine de yazar ki tasarımcı
  /// evlumba.com üzerinden görebilsin.
  static Future<void> _bridgeToEvlumba({
    required String designerId,
    required String body,
    required String koalaConversationId,
    String? attachmentUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final apiUrl = Env.koalaApiUrl;
    if (apiUrl.isEmpty) return;

    final payload = <String, dynamic>{
      'firebaseUid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'avatarUrl': user.photoURL,
      'designerId': designerId,
      'body': body,
      'koalaConversationId': koalaConversationId,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    };

    final ok = await _postBridge(payload);
    if (!ok) {
      // Başarısız — retry queue'ya persist et.
      await _enqueueFailedBridge(payload);
    }
  }

  /// Tek bir bridge POST — başarılı ise true döner. 2xx dışı veya exception false.
  static Future<bool> _postBridge(Map<String, dynamic> payload) async {
    final apiUrl = Env.koalaApiUrl;
    if (apiUrl.isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$apiUrl/api/messages/bridge'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('MessagingService: bridge ok ${res.body}');
        return true;
      } else {
        debugPrint(
            'MessagingService: bridge failed ${res.statusCode} ${res.body}');
        return false;
      }
    } catch (e) {
      // Non-fatal — bridge çalışmasa bile Koala tarafı düzgün çalışır.
      debugPrint('MessagingService: bridge error $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // BRIDGE RETRY QUEUE (local persistence)
  // ═══════════════════════════════════════════════════════
  static const String _retryQueueKey = 'koala_messaging_retry_queue';
  static const int _retryQueueMax = 50;
  static bool _retryInFlight = false;

  static Future<List<Map<String, dynamic>>> _readQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_retryQueueKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } catch (e) {
      debugPrint('MessagingService: readQueue error $e');
    }
    return [];
  }

  static Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (queue.isEmpty) {
        await prefs.remove(_retryQueueKey);
      } else {
        await prefs.setString(_retryQueueKey, jsonEncode(queue));
      }
    } catch (e) {
      debugPrint('MessagingService: writeQueue error $e');
    }
  }

  static Future<void> _enqueueFailedBridge(
      Map<String, dynamic> payload) async {
    final queue = await _readQueue();
    queue.add({
      ...payload,
      '_enqueuedAt': DateTime.now().toIso8601String(),
    });
    // Cap: overflow varsa en eskileri at.
    while (queue.length > _retryQueueMax) {
      queue.removeAt(0);
    }
    await _writeQueue(queue);
    debugPrint('MessagingService: bridge enqueued (size=${queue.length})');
  }

  /// Kuyruktaki başarısız bridge mesajlarını sırayla tekrar dener.
  /// Her payload için 3 deneme, exponential backoff (1s, 2s, 4s).
  /// Başarılı olanlar kuyruktan silinir, başarısızlar kalır.
  /// Eş zamanlı çağrıları önlemek için içsel lock vardır.
  static Future<void> retryQueuedMessages() async {
    if (_retryInFlight) return;
    _retryInFlight = true;
    try {
      final queue = await _readQueue();
      if (queue.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final item in queue) {
        final payload = Map<String, dynamic>.from(item)..remove('_enqueuedAt');
        bool success = false;
        const delays = [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ];
        for (int attempt = 0; attempt < 3; attempt++) {
          await Future.delayed(delays[attempt]);
          success = await _postBridge(payload);
          if (success) break;
        }
        if (!success) {
          remaining.add(item); // başarısız — kuyrukta tut
        }
      }
      await _writeQueue(remaining);
      debugPrint(
          'MessagingService: retry finished (remaining=${remaining.length})');
    } finally {
      _retryInFlight = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // REALTIME (canli dinleme)
  // ═══════════════════════════════════════════════════════

  /// Bir sohbetin mesajlarini canli dinle
  /// Yeni mesaj geldiginde [onMessage] callback cagirilir.
  static void subscribeToMessages({
    required String conversationId,
    required void Function(Map<String, dynamic> message) onMessage,
  }) {
    // Onceki subscription varsa kapat
    unsubscribeFromMessages(conversationId);

    final channelName = 'messages:$conversationId';
    final channel = _db.channel(channelName);

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'koala_direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty) {
              onMessage(Map<String, dynamic>.from(newRecord));
            }
          },
        )
        .subscribe();

    _channels[conversationId] = channel;
    debugPrint('MessagingService: subscribed to $channelName');
  }

  // Çoklu listener desteği — HomeScreen ve ChatListScreen aynı anda abone
  // olabiliyor. Tek channel paylaşılır, her event tüm listener'lara fan-out.
  static final Set<void Function(Map<String, dynamic>)> _convListeners = {};

  /// Conversations listesini canli dinle (son mesaj degisiklikleri).
  /// Aynı listener fonksiyonunu ikinci kez eklemek no-op. Aynı reference
  /// dispose'da [unsubscribeFromConversations(listener: ...)] ile verilmeli.
  static void subscribeToConversations({
    required void Function(Map<String, dynamic> conversation) onUpdate,
  }) {
    if (_uid == null) return;

    _convListeners.add(onUpdate);

    // Channel zaten kurulu mu? Kuruluysa sadece listener'ı ekle.
    if (_channels.containsKey('_conversations')) return;

    final channel = _db.channel('conversations:$_uid');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'koala_conversations',
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isEmpty) return;
            // Sadece kendi sohbetlerimizi dinle
            final userId = record['user_id'];
            final designerId = record['designer_id'];
            if (userId != _uid && designerId != _uid) return;
            // Tüm listener'lara fan-out (kopya liste — iter sırasında remove
            // olabileceği için)
            for (final l in List.of(_convListeners)) {
              try {
                l(Map<String, dynamic>.from(record));
              } catch (_) {}
            }
          },
        )
        .subscribe();

    _channels['_conversations'] = channel;
    debugPrint('MessagingService: subscribed to conversations');
  }

  /// Mesaj subscription'i kapat
  static void unsubscribeFromMessages(String conversationId) {
    final channel = _channels.remove(conversationId);
    if (channel != null) {
      _db.removeChannel(channel);
      debugPrint('MessagingService: unsubscribed from messages:$conversationId');
    }
  }

  /// Conversations subscription'i kapat.
  /// [listener] verilirse sadece o listener kaldırılır; başka listener kalmazsa
  /// channel da tear down edilir. [listener] null ise tüm listener'lar silinir
  /// ve channel kapatılır (geriye dönük uyumluluk için).
  static void unsubscribeFromConversations({
    void Function(Map<String, dynamic>)? listener,
  }) {
    if (listener != null) {
      _convListeners.remove(listener);
      if (_convListeners.isNotEmpty) return;
    } else {
      _convListeners.clear();
    }
    final channel = _channels.remove('_conversations');
    if (channel != null) {
      _db.removeChannel(channel);
      debugPrint('MessagingService: unsubscribed from conversations');
    }
  }

  /// Tum subscription'lari kapat (dispose)
  static void disposeAll() {
    for (final channel in _channels.values) {
      _db.removeChannel(channel);
    }
    _channels.clear();
    debugPrint('MessagingService: all channels disposed');
  }

  // ═══════════════════════════════════════════════════════
  // BADGE & COUNTS
  // ═══════════════════════════════════════════════════════

  /// Toplam okunmamis mesaj sayisi (bildirim badge icin).
  /// unread_count_user / unread_count_designer kolonlarindan hesaplar.
  static Future<int> getUnreadCount() async {
    if (!Env.hasSupabaseConfig) return 0;
    final uid = await _waitForUid();
    if (uid == null) return 0;
    try {
      final res = await _db
          .from('koala_conversations')
          .select('user_id, designer_id, unread_count_user, unread_count_designer, status')
          .or('user_id.eq.$uid,designer_id.eq.$uid');
      final list = List<Map<String, dynamic>>.from(res);
      int total = 0;
      for (final conv in list) {
        if (conv['status'] == 'archived') continue;
        if (conv['user_id'] == uid) {
          total += (conv['unread_count_user'] as int?) ?? 0;
        } else {
          total += (conv['unread_count_designer'] as int?) ?? 0;
        }
      }
      debugPrint('getUnreadCount: ${list.length} conv(s) → total=$total');
      return total;
    } catch (e) {
      debugPrint('MessagingService.getUnreadCount error: $e');
      return 0;
    }
  }

  /// Tek conversation icin okunmamis mesaj sayisi
  static Future<int> getConversationUnreadCount(String conversationId) async {
    if (_uid == null || !Env.hasSupabaseConfig) return 0;
    try {
      final conv = await _db
          .from('koala_conversations')
          .select('user_id, designer_id, unread_count_user, unread_count_designer')
          .eq('id', conversationId)
          .single();

      if (conv['user_id'] == _uid) {
        return (conv['unread_count_user'] as int?) ?? 0;
      }
      return (conv['unread_count_designer'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Alias — badge icin toplam okunmamis
  static Future<int> getTotalUnreadCount() => getUnreadCount();
}
