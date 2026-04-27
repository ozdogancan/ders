import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/koala_tokens.dart';
import '../../services/pro_match_service.dart';
import '../conversation_detail_screen.dart';
import '../mekan/widgets/mekan_ui.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Pro detay ekranı — portföy grid'i, bio, rating, CTA.
/// Chat Sprint 4'te geldikten sonra "İletişime geç" → DM.
/// Şimdilik WhatsApp deep-link MVP.
class ProProfileScreen extends StatefulWidget {
  final ProMatch pro;

  const ProProfileScreen({super.key, required this.pro});

  @override
  State<ProProfileScreen> createState() => _ProProfileScreenState();
}

class _ProProfileScreenState extends State<ProProfileScreen> {
  late Future<List<ProPortfolioItem>> _portfolio;

  /// pros.designer_id (Firebase UID) — legacy chat bridge. Doluysa in-app
  /// chat açılır; null ise WhatsApp fallback.
  String? _designerId;
  bool _designerIdLoaded = false;

  @override
  void initState() {
    super.initState();
    _portfolio = ProMatch.portfolioFor(widget.pro.id);
    _loadDesignerId();
  }

  Future<void> _loadDesignerId() async {
    try {
      final res = await Supabase.instance.client
          .from('pros')
          .select('designer_id')
          .eq('id', widget.pro.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _designerId = res?['designer_id']?.toString();
        _designerIdLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _designerIdLoaded = true);
    }
  }

  Future<void> _openChat() async {
    final did = _designerId;
    if (did == null || did.isEmpty) {
      // Fallback: WhatsApp — pros.designer_id henüz set edilmemiş demo pro.
      return _contactWhatsapp();
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConversationDetailScreen(
        designerId: did,
        designerName: widget.pro.name,
        designerAvatarUrl: widget.pro.profileImageUrl,
        projectTitle: 'Mekan tasarımı',
        initialDraft:
            'Merhaba ${widget.pro.name}, Koala üzerinden mekanımı sizinle '
            'tasarlamak istiyorum.',
      ),
    ));
  }

  Future<void> _contactWhatsapp() async {
    final uri = widget.pro.whatsappUri(
      prefilledMessage:
          'Merhaba ${widget.pro.name}, Koala üzerinden sizinle mekan '
          'tasarımı görüşmek istiyorum.',
    );
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu pro için iletişim henüz aktif değil.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pro;
    return Scaffold(
      backgroundColor: KoalaColors.bg,
      appBar: AppBar(
        backgroundColor: KoalaColors.bg,
        surfaceTintColor: KoalaColors.bg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(LucideIcons.arrowLeft),
        ),
        title: Text(p.name, style: KoalaText.h2),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              KoalaSpacing.xl, KoalaSpacing.md, KoalaSpacing.xl, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: avatar + isim + rating + city
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(KoalaRadius.lg),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: p.profileImageUrl != null
                          ? Image.network(
                              p.profileImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _fallback(),
                            )
                          : _fallback(),
                    ),
                  ),
                  const SizedBox(width: KoalaSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name, style: KoalaText.h1),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(LucideIcons.star,
                                color: Color(0xFFF5B400), size: 16),
                            const SizedBox(width: 3),
                            Text(
                              p.rating.toStringAsFixed(1),
                              style: KoalaText.bodySec
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (p.city != null) ...[
                              const SizedBox(width: 10),
                              const Icon(LucideIcons.mapPin,
                                  size: 14, color: KoalaColors.textSec),
                              const SizedBox(width: 2),
                              Text(p.city!, style: KoalaText.bodySec),
                            ],
                          ],
                        ),
                        if (p.yearsExperience != null) ...[
                          const SizedBox(height: 2),
                          Text('${p.yearsExperience}+ yıl deneyim',
                              style: KoalaText.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoalaSpacing.lg),

              // Stil rozetleri
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: p.topStyles
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: KoalaColors.accentDeep.withValues(alpha: 0.10),
                            borderRadius:
                                BorderRadius.circular(KoalaRadius.pill),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: KoalaColors.accentDeep,
                            ),
                          ),
                        ))
                    .toList(),
              ),

              if (p.bio != null && p.bio!.isNotEmpty) ...[
                const SizedBox(height: KoalaSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(KoalaSpacing.md),
                  decoration: BoxDecoration(
                    color: KoalaColors.surface,
                    borderRadius: BorderRadius.circular(KoalaRadius.md),
                    border: Border.all(color: KoalaColors.border, width: 0.5),
                  ),
                  child: Text(p.bio!, style: KoalaText.bodySec),
                ),
              ],

              const SizedBox(height: KoalaSpacing.lg),

              // Fiyat kartı
              Container(
                padding: const EdgeInsets.all(KoalaSpacing.md),
                decoration: BoxDecoration(
                  color: KoalaColors.accentDeep.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(KoalaRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.creditCard,
                        size: 18, color: KoalaColors.accentDeep),
                    const SizedBox(width: KoalaSpacing.sm),
                    Expanded(
                      child: Text(
                        p.avgPricePerSqm != null
                            ? 'Ortalama ~₺${p.avgPricePerSqm!.round()}/m² '
                                '· proje bazlı detaylı teklif alabilirsiniz'
                            : 'Fiyat projenize göre belirlenir — mesajla sorabilirsiniz',
                        style: KoalaText.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: KoalaColors.accentDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: KoalaSpacing.xl),
              const Text('Portföy', style: KoalaText.h2),
              const SizedBox(height: KoalaSpacing.md),

              FutureBuilder<List<ProPortfolioItem>>(
                future: _portfolio,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              KoalaColors.accentDeep),
                          strokeWidth: 2.5,
                        ),
                      ),
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return Container(
                      height: 120,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: KoalaColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                      ),
                      child: Text('Henüz portföy eklenmemiş',
                          style: KoalaText.bodySec),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(KoalaRadius.md),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              it.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: KoalaColors.surfaceAlt,
                              ),
                            ),
                            if (it.styleLabel != null)
                              Positioned(
                                left: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius:
                                        BorderRadius.circular(KoalaRadius.pill),
                                  ),
                                  child: Text(
                                    it.styleLabel!,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                          .animate(delay: (i * 60).ms)
                          .fadeIn(duration: 280.ms)
                          .scaleXY(begin: 0.95, end: 1.0);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KoalaSpacing.xl),
          child: _buildPrimaryCta(p),
        ),
      ),
    );
  }

  /// In-app chat hazırsa "Sohbet Başlat", değilse WhatsApp fallback.
  /// Henüz designer_id fetch edilmediyse yükleniyor göster.
  Widget _buildPrimaryCta(ProMatch p) {
    if (!_designerIdLoaded) {
      return MekanPrimaryButton(
        label: 'Yükleniyor…',
        onTap: () {},
        trailing: LucideIcons.hourglass,
      );
    }
    final canChat = (_designerId != null && _designerId!.isNotEmpty);
    if (canChat) {
      return MekanPrimaryButton(
        label: 'Sohbet Başlat',
        onTap: _openChat,
        trailing: LucideIcons.messageCircle,
      );
    }
    if (p.contactWhatsapp != null) {
      return MekanPrimaryButton(
        label: 'WhatsApp\'tan mesaj gönder',
        onTap: _contactWhatsapp,
        trailing: LucideIcons.messageCircle,
      );
    }
    return MekanPrimaryButton(
      label: 'İletişim yakında aktif',
      onTap: () => _contactWhatsapp(),
      trailing: LucideIcons.mail,
    );
  }

  Widget _fallback() => Container(
        color: KoalaColors.surfaceAlt,
        alignment: Alignment.center,
        child: Text(
          widget.pro.name.isEmpty ? '?' : widget.pro.name[0].toUpperCase(),
          style: KoalaText.h1.copyWith(color: KoalaColors.textSec),
        ),
      );
}
