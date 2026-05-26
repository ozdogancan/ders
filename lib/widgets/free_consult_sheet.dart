// Evlumba Design için tek noktadan "Sohbet Başlat" girişi.
//
// Davranış:
//   1) Pro kullanıcı           → popup yok, doğrudan tek-konuşmaya gir.
//   2) Pro değil + ilk danışma henüz kullanılmamış (Evlumba conv'a sender
//      olarak hiç mesaj atılmamış) → "İlk danışma ücretsizdir" sheet aç.
//      CTA "Sohbet Başlat" tıklanınca konuşmaya gir.
//   3) Pro değil + ilk danışma KULLANILMIŞ → popup yok, doğrudan konuşmaya
//      gir (chat ekranı send gate ile paywall'ı zaten halleder).
//
// "Tek konuşma" politikası: MessagingService.findOrCreateEvlumbaConversation
// her zaman aynı user_id + designer_id='evlumba-design' satırını döndürür.
// Yoksa yaratır.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/koala_tokens.dart';
import '../providers/pro_status_provider.dart';
import '../services/messaging_service.dart';

const String _kEvlumbaDesignerId = 'evlumba-design';
const String _kEvlumbaAvatarUrl =
    'https://xgefjepaqnghaotqybpi.supabase.co/storage/v1/object/public/koala-seed/avatars/evlumba-design.webp';

/// Process-lifetime cache — ilk lookup'tan sonra Evlumba conv id ve
/// free-consult kullanım durumu cache'lenir. Sonraki tüm "Evlumba'ya
/// sor" tıklamaları anında (network yok) chat ekranına geçer.
String? _cachedEvlumbaConvId;
bool? _cachedFreeConsultUsed; // null = bilinmiyor

/// Chat list açıldığında veya başka uygun bir noktada arka planda
/// Evlumba conversation'ı ve free-consult durumunu prefetch eder.
/// Tap anında network beklemesi olmasın diye.
Future<void> prewarmEvlumbaConversation() async {
  if (_cachedEvlumbaConvId != null) return;
  try {
    final conv = await MessagingService.findOrCreateEvlumbaConversation();
    final id = conv?['id']?.toString();
    if (id != null && id.isNotEmpty) {
      _cachedEvlumbaConvId = id;
      // Free-consult bayrağını paralel ısıt.
      MessagingService.hasUsedFreeConsult(id).then((used) {
        _cachedFreeConsultUsed = used;
      });
    }
  } catch (_) {/* sessiz — tap anında fallback path çalışır */}
}

/// Cache'i temizle (örn. logout sonrası başka kullanıcı için).
void resetEvlumbaConversationCache() {
  _cachedEvlumbaConvId = null;
  _cachedFreeConsultUsed = null;
}

/// Evlumba Design konuşmasına giriş için tek noktadan helper.
/// Tüm "Evlumba'ya sor" / "Sohbet Başlat" entry point'leri bunu çağırır.
///
/// HIZ POLİTİKASI:
///   - Pro kullanıcı + cache hit → ANINDA push (await yok)
///   - Cache hit + free-consult cached false → ANINDA push
///   - Cache miss → lookup'ı await et ama UI'da hint bırakma
///     (sub-300ms hedef)
Future<void> enterEvlumbaConversation(
  BuildContext context,
  WidgetRef ref, {
  String? projectTitle,
  Map<String, dynamic>? pendingDesign,
}) async {
  final pro = ref.read(proStatusProvider).value?.isPro ?? false;

  // Fast path — cache hit, popup gerekmiyor → hemen push.
  if (_cachedEvlumbaConvId != null) {
    final convId = _cachedEvlumbaConvId!;
    final needsPopup = !pro && (_cachedFreeConsultUsed == false);
    if (!needsPopup) {
      _pushToConv(context, convId,
          projectTitle: projectTitle, pendingDesign: pendingDesign);
      return;
    }
    // Cache var ama popup gerek → popup'ı göster, ardından push.
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => const FreeConsultSheet(),
    );
    if (go != true || !context.mounted) return;
    _pushToConv(context, convId,
        projectTitle: projectTitle, pendingDesign: pendingDesign);
    return;
  }

  // Cold path — conversation lookup gerekiyor.
  final conv =
      await MessagingService.findOrCreateEvlumbaConversation(title: projectTitle);
  if (conv == null) {
    if (!context.mounted) return;
    final err = MessagingService.lastConvError;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            err == null || err.isEmpty
                ? 'Sohbet başlatılamadı — tekrar deneyin'
                : 'Sohbet başlatılamadı: $err',
          ),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
        ),
      );
    return;
  }
  final convId = conv['id']?.toString();
  if (convId == null || convId.isEmpty) return;
  _cachedEvlumbaConvId = convId;

  // Pro ise popup yok — anında push, free-consult check'i bypass.
  if (pro) {
    if (!context.mounted) return;
    _pushToConv(context, convId,
        projectTitle: projectTitle, pendingDesign: pendingDesign);
    return;
  }

  // Free-consult durumu — Pro değilse hesapla.
  final used = await MessagingService.hasUsedFreeConsult(convId);
  _cachedFreeConsultUsed = used;
  if (!context.mounted) return;

  if (!used) {
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => const FreeConsultSheet(),
    );
    if (go != true || !context.mounted) return;
  }
  _pushToConv(context, convId,
      projectTitle: projectTitle, pendingDesign: pendingDesign);
}

void _pushToConv(
  BuildContext context,
  String convId, {
  String? projectTitle,
  Map<String, dynamic>? pendingDesign,
}) {
  final extra = <String, dynamic>{
    'designerId': _kEvlumbaDesignerId,
    'designerName': 'Evlumba Design',
    'designerAvatarUrl': _kEvlumbaAvatarUrl,
    if (projectTitle != null && projectTitle.isNotEmpty)
      'projectTitle': projectTitle,
    if (pendingDesign != null) 'pendingDesign': pendingDesign,
  };
  context.push('/chat/dm/$convId', extra: extra);
}

/// "İlk danışma ücretsizdir" premium sheet — champagne/altın palette.
/// Pop sonucu `true` ise caller chat ekranına gider, başka değerse iptal.
class FreeConsultSheet extends StatelessWidget {
  const FreeConsultSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad + 24),
      decoration: const BoxDecoration(
        // Premium champagne gradient — Evlumba brand.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF7EE), Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: KoalaColors.borderSolid,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Premium gold icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD4A853), Color(0xFFE8C76A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A853).withValues(alpha: 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.sparkles,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'İlk danışma ücretsiz',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: KoalaColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Evlumba Design stüdyosuyla ilk sohbetin bizden. '
              'Tasarımına dair ne istersen sor — uzmanlar 1 saat içinde döner.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: KoalaColors.textSec,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 24),

          _row(LucideIcons.zap, '1 saat içinde yanıt'),
          const SizedBox(height: 12),
          _row(LucideIcons.badgeCheck, 'Sertifikalı iç mimar'),
          const SizedBox(height: 12),
          _row(LucideIcons.gem, 'Kişiye özel öneri'),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A853),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KoalaRadius.md),
                ),
              ),
              child: const Text(
                'Sohbet Başlat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Şimdi değil',
              style: TextStyle(
                fontSize: 13,
                color: KoalaColors.textTer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label) => Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFDF8EC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFE8D7A8),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFD4A853)),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: KoalaColors.text,
            ),
          ),
        ],
      );
}
